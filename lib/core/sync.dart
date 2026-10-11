import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'config.dart';
import 'db.dart';
import 'modelos.dart';

/// Sincronização: fila de pedidos, situação da conexão, mesas e catálogo.
/// Um único timer leve; pausa com o app em segundo plano.
class SyncService extends ChangeNotifier {
  SyncService(this.config, this.api, this.db);

  final AppConfig config;
  final Api api;
  final LocalDb db;

  /// null = ainda não sabe; true = conectado; false = offline.
  bool? online;
  bool enviando = false;
  int pendentes = 0;
  int erros = 0;
  DateTime? mesasAtualizadasEm;
  String? avisoCatalogo;

  /// Sessão recusada pelo servidor (token/aparelho). Os pedidos ficam guardados.
  final ValueNotifier<ApiException?> sessaoRecusada = ValueNotifier(null);

  /// Tela de mesas visível: só então consulta as mesas periodicamente.
  bool mesasVisiveis = false;

  /// Contador que muda sempre que mesas/pedidos mudam (telas recarregam do SQLite).
  final ValueNotifier<int> versaoDados = ValueNotifier(0);

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _conn;
  bool _ocupado = false;
  String _assinaturaMesas = '';
  DateTime _ultimaConsultaMesas = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ultimoPing = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ultimoCatalogo = DateTime.fromMillisecondsSinceEpoch(0);

  static const _intervaloTick = Duration(seconds: 4);
  static const _intervaloMesas = Duration(seconds: 12);
  static const _intervaloPingOffline = Duration(seconds: 8);
  static const _intervaloCatalogo = Duration(minutes: 20);

  void iniciar() {
    _timer ??= Timer.periodic(_intervaloTick, (_) => _tick());
    _conn ??= Connectivity().onConnectivityChanged.listen((r) {
      if (r.contains(ConnectivityResult.none)) {
        _setOnline(false);
      } else {
        agora();
      }
    });
    atualizarContadores();
    agora();
  }

  void pausar() {
    _timer?.cancel();
    _timer = null;
  }

  void retomar() {
    _timer ??= Timer.periodic(_intervaloTick, (_) => _tick());
    agora();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _conn?.cancel();
    super.dispose();
  }

  /// Executa um ciclo já (Wi-Fi voltou, pedido novo, botão atualizar).
  void agora({bool forcarMesas = false}) {
    if (forcarMesas) _ultimaConsultaMesas = DateTime.fromMillisecondsSinceEpoch(0);
    _ultimoPing = DateTime.fromMillisecondsSinceEpoch(0);
    unawaited(_tick(forcar: true));
  }

  Future<void> _tick({bool forcar = false}) async {
    if (_ocupado || !config.hasSession || sessaoRecusada.value != null) return;
    _ocupado = true;
    try {
      final agora = DateTime.now();

      if (online != true) {
        if (!forcar && agora.difference(_ultimoPing) < _intervaloPingOffline) return;
        _ultimoPing = agora;
        _setOnline(await api.ping());
        if (online != true) return;
      }

      await _enviarFila();

      if (online == true && (mesasVisiveis || forcar) && agora.difference(_ultimaConsultaMesas) >= _intervaloMesas) {
        await atualizarMesas();
      }

      if (online == true && agora.difference(_ultimoCatalogo) >= _intervaloCatalogo) {
        await atualizarCatalogo();
      }
    } finally {
      _ocupado = false;
    }
  }

  Future<void> _enviarFila() async {
    final fila = await db.pedidosParaEnviar(DateTime.now().millisecondsSinceEpoch);
    if (fila.isEmpty) return;

    enviando = true;
    notifyListeners();
    final mesasAdiadas = <int>{};

    try {
      for (final pedido in fila) {
        // Mantém a ordem dos pedidos de uma mesma mesa.
        if (mesasAdiadas.contains(pedido.numero)) continue;

        try {
          final r = await api.lancar(pedido.corpoEnvio());
          if (r['ok'] == true) {
            await db.marcarEnviado(pedido.uuid);
            final mesa = r['mesa'];
            if (mesa is Map<String, dynamic>) {
              await db.salvarMesa(MesaInfo.fromResumo(mesa));
            }
            _setOnline(true);
          } else {
            mesasAdiadas.add(pedido.numero);
            await db.reagendar(pedido.uuid, 'Resposta inesperada do servidor.', _proxima(pedido));
          }
        } on ApiException catch (e) {
          if (e.semConexao) {
            // Pode ter chegado ao servidor: o reenvio com o mesmo uuid não duplica.
            _setOnline(false);
            await db.reagendar(pedido.uuid, e.message, 0);
            break;
          }
          if (e.sessaoInvalida) {
            sessaoRecusada.value = e;
            break;
          }
          if (e.retry) {
            mesasAdiadas.add(pedido.numero);
            await db.reagendar(pedido.uuid, e.message, _proxima(pedido), code: e.code);
            continue;
          }
          mesasAdiadas.add(pedido.numero);
          await db.marcarErro(pedido.uuid, e.code ?? 'ERRO', e.message, e.detalhes);
        }
      }
    } finally {
      enviando = false;
      await atualizarContadores();
    }
  }

  /// 10 s, 20 s, 40 s… até 2 min entre tentativas da mesma falha temporária.
  int _proxima(Pedido p) {
    final segundos = (10 * (1 << p.tentativas.clamp(0, 4))).clamp(10, 120);
    return DateTime.now().add(Duration(seconds: segundos)).millisecondsSinceEpoch;
  }

  Future<void> atualizarMesas() async {
    _ultimaConsultaMesas = DateTime.now();
    try {
      final r = await api.mesas(_assinaturaMesas);
      _setOnline(true);
      mesasAtualizadasEm = DateTime.now();
      if (r['inalterado'] == true) {
        notifyListeners();
        return;
      }
      final qtd = (r['quantidade'] as num?)?.toInt() ?? config.qtdMesas;
      final lista = (r['mesas'] as List<dynamic>? ?? const [])
          .map((l) => MesaInfo.fromApi(l as List<dynamic>))
          .toList();
      await db.substituirMesas(lista);
      _assinaturaMesas = '${r['s'] ?? ''}';
      if (qtd != config.qtdMesas) {
        config.qtdMesas = qtd;
        await config.save();
      }
      versaoDados.value++;
      notifyListeners();
    } on ApiException catch (e) {
      _tratarFalha(e);
    }
  }

  /// Baixa o catálogo só se a versão do servidor mudou.
  Future<bool> atualizarCatalogo({bool forcar = false}) async {
    _ultimoCatalogo = DateTime.now();
    try {
      final r = await api.catalogo(forcar ? '' : config.catalogoVersao);
      _setOnline(true);
      if (r['inalterado'] != true) {
        await db.substituirProdutos(r['produtos'] as List<dynamic>? ?? const []);
        config.catalogoVersao = '${r['versao'] ?? ''}';
        config.catalogoAtualizadoEm = DateTime.now().toIso8601String();
        await config.save();
        versaoDados.value++;
      }
      avisoCatalogo = null;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      avisoCatalogo = e.message;
      _tratarFalha(e);
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> buscarComanda(int numero) async {
    try {
      final r = await api.comanda(numero);
      _setOnline(true);
      await db.salvarComanda(numero, r);
      await db.salvarMesa(MesaInfo.fromResumo(r));
      versaoDados.value++;
      return r;
    } on ApiException catch (e) {
      _tratarFalha(e);
      return null;
    }
  }

  Future<void> atualizarContadores() async {
    final (p, e) = await db.contarPedidos();
    pendentes = p;
    erros = e;
    versaoDados.value++;
    notifyListeners();
  }

  void liberarSessao() {
    sessaoRecusada.value = null;
    _assinaturaMesas = '';
  }

  void _tratarFalha(ApiException e) {
    if (e.semConexao) {
      _setOnline(false);
    } else if (e.sessaoInvalida) {
      sessaoRecusada.value = e;
    }
  }

  void _setOnline(bool valor) {
    if (online == valor) return;
    online = valor;
    notifyListeners();
  }
}
