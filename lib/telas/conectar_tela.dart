import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/descoberta.dart';
import '../core/erp_url.dart';

/// Conexão com o ERP (mesmo padrão da Força de Vendas): reconectar no último
/// servidor, procurar na rede ou informar IP / porta / URL manualmente.
class ConectarTela extends StatefulWidget {
  const ConectarTela({super.key, required this.state});

  final AppState state;

  @override
  State<ConectarTela> createState() => _ConectarTelaState();
}

class _ConectarTelaState extends State<ConectarTela> {
  final _url = TextEditingController();
  bool _ocupado = false;
  bool _procurando = false;
  int _feito = 0;
  int _total = 0;
  String? _status;
  String? _erro;

  String get _ultimo => widget.state.config.lastBaseUrl;

  @override
  void initState() {
    super.initState();
    if (_ultimo.isNotEmpty) _url.text = _semEsquema(_ultimo);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  static String _semEsquema(String url) => url.replaceFirst(RegExp(r'^https?://'), '');

  Future<void> _conectar(String base) async {
    if (base.isEmpty) {
      setState(() => _erro = 'Informe o IP ou o endereço do servidor.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _ocupado = true;
      _erro = null;
      _status = 'Conectando em ${_semEsquema(base)}…';
    });
    try {
      if (!await Api.pingBase(base, timeout: const Duration(seconds: 5))) {
        if (mounted) setState(() => _erro = 'Unitec ERP não respondeu em ${_semEsquema(base)}.');
        return;
      }
      await widget.state.conectar(base);
    } on ApiException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _procurar() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _ocupado = true;
      _procurando = true;
      _erro = null;
      _feito = 0;
      _total = 0;
      _status = 'Procurando servidor na rede…';
    });
    final base = await DescobertaServidor.procurar(
      progresso: (f, t) {
        if (mounted) {
          setState(() {
            _feito = f;
            _total = t;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _procurando = false;
      _status = null;
    });
    if (base == null) {
      setState(() => _erro = 'Servidor não encontrado nesta rede. Informe o IP abaixo.');
      return;
    }
    _url.text = _semEsquema(base);
    await _conectar(base);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ultimo = _ultimo;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.table_restaurant, size: 56, color: cs.primary),
              const SizedBox(height: 8),
              Text('Unitec Mesas',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Conecte ao servidor do Unitec ERP',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 28),
              if (ultimo.isNotEmpty) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _ocupado ? null : () => _conectar(ultimo),
                  icon: const Icon(Icons.refresh),
                  label: Text('Reconectar (${_semEsquema(ultimo)})', overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _ocupado ? null : _procurar,
                icon: const Icon(Icons.wifi_find),
                label: const Text('Procurar servidor na rede'),
              ),
              if (_procurando) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: _total > 0 ? _feito / _total : null),
                const SizedBox(height: 4),
                Text(
                  _total > 0 ? 'Verificando $_feito de $_total endereços…' : 'Lendo a rede Wi-Fi…',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ou', style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: _url,
                enabled: !_ocupado,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                decoration: const InputDecoration(
                  labelText: 'IP do servidor',
                  hintText: '192.168.0.10  (porta 8765 é o padrão)',
                  helperText: 'Aceita IP, IP:porta (ex.: 192.168.0.10:8000) ou URL',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                onSubmitted: (_) => _conectar(ErpUrl.normalize(_url.text)),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _ocupado ? null : () => _conectar(ErpUrl.normalize(_url.text)),
                child: const Text('Conectar por IP'),
              ),
              if (_status != null && !_procurando) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_status!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 16),
                Text(_erro!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
              ],
              const SizedBox(height: 24),
              Text('Versão $kAppVersion',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}
