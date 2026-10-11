import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'widgets.dart';

/// Aparelho registrado: bloqueado até o administrador autorizar no ERP
/// (Terminais → Aparelhos), igual Força de Vendas.
class AguardandoTela extends StatefulWidget {
  const AguardandoTela({super.key, required this.state});

  final AppState state;

  @override
  State<AguardandoTela> createState() => _AguardandoTelaState();
}

class _AguardandoTelaState extends State<AguardandoTela> {
  Timer? _timer;
  String? _erro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _verificar();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _verificar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verificar() async {
    if (_ocupado) return;
    _ocupado = true;
    try {
      await widget.state.verificarAprovacao();
      if (mounted) setState(() => _erro = null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } finally {
      _ocupado = false;
    }
  }

  Future<void> _executar(Future<void> Function() acao) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await acao();
      if (mounted) setState(() => _erro = null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _editarNome() async {
    final ctrl = TextEditingController(text: widget.state.config.deviceName);
    final nome = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nome do aparelho'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(hintText: 'Ex.: Garçom salão 1'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Salvar')),
        ],
      ),
    );
    ctrl.dispose();
    if (nome == null || !mounted) return;
    await _executar(() => widget.state.renomearAparelho(nome));
  }

  Future<void> _trocarServidor() async {
    if (await confirmar(context, 'Trocar servidor',
        'Voltar para a tela de conexão? O endereço atual continua salvo para reconectar.')) {
      await widget.state.trocarServidor();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final cfg = st.config;
    final cs = Theme.of(context).colorScheme;
    final revogado = st.aparelhoStatus == 'revogado';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(revogado ? Icons.block : Icons.phonelink_lock,
                  size: 52, color: revogado ? cs.error : cs.primary),
              const SizedBox(height: 12),
              Text(revogado ? 'Acesso revogado' : 'Aguardando autorização',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                revogado
                    ? 'O acesso deste aparelho foi revogado no Unitec ERP. Solicite novamente e peça para autorizar em Terminais → Aparelhos.'
                    : 'No Unitec ERP, abra Terminais → Aparelhos e autorize este aparelho.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (!revogado) ...[
                Text('Código', style: TextStyle(color: cs.onSurfaceVariant)),
                SelectableText(
                  cfg.pairingCode.isEmpty ? '------' : cfg.pairingCode,
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6),
                ),
              ],
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(cfg.deviceName,
                      overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                IconButton(
                  tooltip: 'Alterar nome do aparelho',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: _ocupado ? null : _editarNome,
                ),
              ]),
              const SizedBox(height: 12),
              if (revogado)
                FilledButton.icon(
                  onPressed: _ocupado ? null : () => _executar(st.solicitarNovamente),
                  icon: const Icon(Icons.send),
                  label: const Text('Solicitar novamente'),
                )
              else
                const SizedBox(width: 160, child: LinearProgressIndicator()),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
              ],
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _trocarServidor,
                icon: const Icon(Icons.dns_outlined, size: 18),
                label: Text('Trocar servidor (${cfg.baseUrl.replaceFirst(RegExp(r'^https?://'), '')})'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
