import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'telas/aguardando_tela.dart';
import 'telas/conectar_tela.dart';
import 'telas/login_tela.dart';
import 'telas/mesas_tela.dart';
import 'update/app_updater.dart';
import 'update/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final state = await AppState.iniciar();
  runApp(UnitecMesasApp(state: state));
}

const corMarca = Color(0xFF1E5A9E);

class UnitecMesasApp extends StatefulWidget {
  const UnitecMesasApp({super.key, required this.state});

  final AppState state;

  @override
  State<UnitecMesasApp> createState() => _UnitecMesasAppState();
}

class _UnitecMesasAppState extends State<UnitecMesasApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fora da inicialização: a primeira tela abre antes da consulta ao GitHub.
    Future.delayed(const Duration(seconds: 4), _verificarAtualizacao);
  }

  Future<void> _verificarAtualizacao() async {
    final release = await AppUpdater.instance.verificar();
    if (release == null || !mounted) return;
    final ctx = _navigator.currentState?.overlay?.context;
    if (ctx == null || !ctx.mounted) return;
    await mostrarAtualizacaoDisponivel(ctx, release);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final st = widget.state;
    if (st.etapa != Etapa.mesas) return;
    if (s == AppLifecycleState.resumed) {
      st.sync.retomar();
    } else if (s == AppLifecycleState.paused) {
      st.sync.pausar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'Unitec Mesas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: corMarca),
        visualDensity: VisualDensity.compact,
        useMaterial3: true,
        // Transição simples: mais leve em celular fraco.
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        }),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final st = widget.state;
          return switch (st.etapa) {
            Etapa.conectar => ConectarTela(state: st),
            Etapa.aguardandoAprovacao => AguardandoTela(state: st),
            Etapa.login => LoginTela(state: st),
            Etapa.mesas => MesasTela(state: st),
          };
        },
      ),
    );
  }
}
