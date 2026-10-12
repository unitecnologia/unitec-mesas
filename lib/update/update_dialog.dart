import 'package:flutter/material.dart';

import '../app_info.dart';
import 'app_updater.dart';

enum _Etapa { oferta, baixando, permissao, erro }

/// "Nova atualização disponível": só baixa e abre o instalador após OK.
/// O modal fecha antes do instalador Android — nunca fica atrás dele.
Future<void> mostrarAtualizacaoDisponivel(BuildContext context, AppRelease release) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => _UpdateDialog(release: release),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release});

  final AppRelease release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> with WidgetsBindingObserver {
  final _updater = AppUpdater.instance;
  _Etapa _etapa = _Etapa.oferta;
  int _recebido = 0;
  int _total = 0;
  String? _arquivo;
  String _erro = '';
  bool _abrindoInstalador = false;
  bool _aguardandoPermissao = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou da tela "Permitir desta fonte": segue para o instalador se liberou.
    if (state == AppLifecycleState.resumed &&
        _aguardandoPermissao &&
        _etapa == _Etapa.permissao &&
        !_abrindoInstalador) {
      _aguardandoPermissao = false;
      _abrirInstalador();
    }
  }

  Future<void> _atualizar() async {
    if (_updater.baixando && _etapa == _Etapa.baixando) return;
    setState(() {
      _etapa = _Etapa.baixando;
      _recebido = 0;
      _total = widget.release.apkSize;
      _erro = '';
    });
    try {
      _arquivo = await _updater.baixar(widget.release, progresso: (recebido, total) {
        if (!mounted) return;
        setState(() {
          _recebido = recebido;
          _total = total;
        });
      });
      await _abrirInstalador();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is AtualizacaoException ? e.message : 'Não foi possível baixar a atualização. Tente novamente.';
        _etapa = _Etapa.erro;
      });
    }
  }

  /// Fecha o modal e só então abre o instalador Android.
  Future<void> _abrirInstalador() async {
    final arquivo = _arquivo;
    if (arquivo == null || _abrindoInstalador) return;

    try {
      if (!await _updater.podeInstalar()) {
        if (mounted) {
          setState(() {
            _etapa = _Etapa.permissao;
            _aguardandoPermissao = false;
          });
        }
        return;
      }

      if (!mounted) return;
      _abrindoInstalador = true;

      // Fecha o diálogo interno antes do instalador (evita overlay atrás).
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();

      // Deixa o frame do pop completar antes do startActivity.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      try {
        final ok = await _updater.instalar(arquivo);
        if (!ok) {
          debugPrint('Atualização: instalador não abriu (arquivo inválido ou URI).');
        }
      } catch (e) {
        debugPrint('Atualização: falha ao abrir instalador ($e)');
      }
    } catch (e) {
      _abrindoInstalador = false;
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível abrir o instalador do Android.';
        _etapa = _Etapa.erro;
      });
    }
  }

  Future<void> _abrirPermissao() async {
    _aguardandoPermissao = true;
    await _updater.abrirPermissaoInstalacao();
  }

  void _fechar() {
    if (_etapa == _Etapa.baixando) _updater.cancelar();
    _aguardandoPermissao = false;
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final erro = _etapa == _Etapa.erro;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _fechar();
      },
      child: AlertDialog(
        icon: Icon(erro ? Icons.error_outline : Icons.system_update, color: erro ? cs.error : cs.primary),
        title: const Text('Atualização do Unitec Mesas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versão atual: $kAppVersion ($kAppBuild)'),
            const SizedBox(height: 2),
            Text(
              'Nova versão: ${widget.release.versionName}'
              '${widget.release.versionCode != null ? ' (${widget.release.versionCode})' : ''}',
              style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
            ),
            const SizedBox(height: 14),
            ..._conteudo(cs),
          ],
        ),
        actions: _botoes(),
      ),
    );
  }

  List<Widget> _conteudo(ColorScheme cs) {
    switch (_etapa) {
      case _Etapa.oferta:
        return [
          const Text('Nova atualização disponível. Deseja atualizar agora?',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Configurações, login e pedidos pendentes continuam no aparelho.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ];
      case _Etapa.baixando:
        final fracao = _total > 0 ? (_recebido / _total).clamp(0.0, 1.0) : null;
        return [
          LinearProgressIndicator(value: fracao, minHeight: 6),
          const SizedBox(height: 8),
          Text(
            fracao == null
                ? 'Baixando… ${_mb(_recebido)} MB'
                : 'Baixando… ${(fracao * 100).toStringAsFixed(0)}%  (${_mb(_recebido)} de ${_mb(_total)} MB)',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ];
      case _Etapa.permissao:
        return const [
          Text('Para atualizar, o Android precisa liberar a instalação por este app.\n\n'
              'Toque em "Abrir configuração", ative "Permitir desta fonte" e volte ao app.'),
        ];
      case _Etapa.erro:
        return [Text(_erro, style: TextStyle(color: cs.error))];
    }
  }

  List<Widget> _botoes() {
    switch (_etapa) {
      case _Etapa.oferta:
        return [
          TextButton(onPressed: _fechar, child: const Text('Depois')),
          FilledButton(onPressed: _atualizar, child: const Text('OK')),
        ];
      case _Etapa.baixando:
        return [TextButton(onPressed: _fechar, child: const Text('Cancelar'))];
      case _Etapa.permissao:
        return [
          TextButton(onPressed: _fechar, child: const Text('Depois')),
          FilledButton(onPressed: _abrirPermissao, child: const Text('Abrir configuração')),
        ];
      case _Etapa.erro:
        return [
          TextButton(onPressed: _fechar, child: const Text('Depois')),
          FilledButton(onPressed: _atualizar, child: const Text('Tentar de novo')),
        ];
    }
  }
}
