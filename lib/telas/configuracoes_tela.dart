import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/app_state.dart';
import '../update/app_updater.dart';
import '../update/update_dialog.dart';
import 'widgets.dart';

/// Configurações do app: versão e verificação manual de atualização.
/// Não altera login, SQLite nem pedidos pendentes.
class ConfiguracoesTela extends StatefulWidget {
  const ConfiguracoesTela({super.key, required this.state});

  final AppState state;

  @override
  State<ConfiguracoesTela> createState() => _ConfiguracoesTelaState();
}

class _ConfiguracoesTelaState extends State<ConfiguracoesTela> {
  bool _verificando = false;

  Future<void> _verificarAtualizacoes() async {
    if (_verificando) return;
    setState(() => _verificando = true);
    try {
      final resultado = await AppUpdater.instance.consultar(forcar: true);
      if (!mounted) return;
      final release = resultado.release;
      if (release != null) {
        await mostrarAtualizacaoDisponivel(context, release);
        return;
      }
      if (!mounted) return;
      avisar(
        context,
        resultado.falhou
            ? 'Não foi possível consultar a atualização. Verifique a internet.'
            : 'O aplicativo já está na versão mais recente ($kAppVersion).',
        erro: resultado.falhou,
      );
    } catch (_) {
      if (!mounted) return;
      avisar(context, 'Não foi possível consultar a atualização. Verifique a internet.', erro: true);
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.state.config;
    final cs = Theme.of(context).colorScheme;
    final servidor = cfg.baseUrl.replaceFirst(RegExp(r'^https?://'), '');

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline, color: cs.primary),
            title: const Text('Unitec Mesas'),
            subtitle: Text('Versão $kAppVersion ($kAppBuild)'),
          ),
          if (servidor.isNotEmpty) ...[
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.dns_outlined, color: cs.primary),
              title: const Text('Servidor'),
              subtitle: Text(servidor),
            ),
          ],
          const Divider(height: 24),
          Text(
            'Atualização',
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Consulta a versão publicada no GitHub. Configurações, login e pedidos '
            'pendentes continuam no aparelho.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _verificando ? null : _verificarAtualizacoes,
            icon: _verificando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
            label: Text(_verificando ? 'Verificando…' : 'Verificar atualizações'),
          ),
        ],
      ),
    );
  }
}
