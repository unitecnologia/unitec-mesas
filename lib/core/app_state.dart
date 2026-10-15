import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'config.dart';
import 'db.dart';
import 'sync.dart';

enum Etapa { conectar, aguardandoAprovacao, login, mesas }

class AppState extends ChangeNotifier {
  AppState._(this.config, this.db) : api = Api(config) {
    sync = SyncService(config, api, db);
    sync.sessaoRecusada.addListener(_onSessaoRecusada);
  }

  final AppConfig config;
  final LocalDb db;
  final Api api;
  late final SyncService sync;

  Etapa etapa = Etapa.conectar;

  static Future<AppState> iniciar() async {
    final config = await AppConfig.load();
    final db = await LocalDb.open();
    final state = AppState._(config, db);
    await state._garantirAparelho();
    await db.limparHistorico();

    // Reinício do app: confirma aprovação no servidor com o mesmo UUID.
    // Só pede autorização de novo se o aparelho for novo/revogado (ex.: app desinstalado).
    if (config.isConnected && config.deviceUuid.isNotEmpty) {
      try {
        await state.verificarAprovacao();
      } catch (_) {
        // Offline ou falha temporária: mantém o que está salvo no celular.
      }
    }

    if (config.hasSession) {
      state.etapa = Etapa.mesas;
      state.sync.iniciar();
    } else if (config.isConnected && config.deviceApproved) {
      state.etapa = Etapa.login;
    } else if (config.isConnected) {
      state.etapa = Etapa.aguardandoAprovacao;
    }
    return state;
  }

  Future<void> _garantirAparelho() async {
    if (config.deviceUuid.isEmpty) {
      config.deviceUuid = const Uuid().v4();
    }
    if (config.deviceName.isEmpty) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        config.deviceName = '${info.manufacturer} ${info.model}'.trim();
      } catch (_) {
        config.deviceName = 'Android';
      }
    }
    await config.save();
  }

  /// pendente / aprovado / revogado (tela de aguardando aprovação).
  String aparelhoStatus = 'pendente';

  /// Salva o servidor e registra o aparelho (aprovação no ERP: Terminais → Aparelhos).
  Future<void> conectar(String baseUrl) async {
    final anterior = config.baseUrl;
    config.baseUrl = baseUrl;
    final Map<String, dynamic> r;
    try {
      r = await api.registrarAparelho();
    } catch (_) {
      config.baseUrl = anterior;
      rethrow;
    }
    config.lastBaseUrl = baseUrl;
    _aplicarAparelho(r);
    await config.save();
    etapa = config.deviceApproved ? Etapa.login : Etapa.aguardandoAprovacao;
    notifyListeners();
  }

  /// Consulta a aprovação. Aparelho excluído no ERP volta a pedir aprovação;
  /// revogado só pede de novo pelo botão (igual Força de Vendas).
  Future<bool> verificarAprovacao() async {
    var r = await api.statusAparelho();
    if (r['status'] == 'desconhecido') {
      r = await api.registrarAparelho();
    }
    _aplicarAparelho(r);
    await config.save();
    if (config.deviceApproved) etapa = Etapa.login;
    notifyListeners();
    return config.deviceApproved;
  }

  Future<void> solicitarNovamente() async {
    _aplicarAparelho(await api.registrarAparelho());
    await config.save();
    if (config.deviceApproved) etapa = Etapa.login;
    notifyListeners();
  }

  Future<void> renomearAparelho(String nome) async {
    final n = nome.trim();
    if (n.isEmpty || n == config.deviceName) return;
    config.deviceName = n;
    await config.save();
    await solicitarNovamente();
  }

  /// ERP recusou o aparelho (excluído/revogado): volta a bloquear até nova aprovação.
  Future<void> aparelhoRecusado() async {
    config.deviceApproved = false;
    await config.save();
    etapa = Etapa.aguardandoAprovacao;
    notifyListeners();
  }

  void _aplicarAparelho(Map<String, dynamic> r) {
    final codigo = '${r['pairing_code'] ?? ''}';
    if (codigo.isNotEmpty) config.pairingCode = codigo;
    config.deviceApproved = r['approved'] == true;
    aparelhoStatus = config.deviceApproved ? 'aprovado' : '${r['status'] ?? 'pendente'}';
  }

  Future<void> entrar({required int empresaId, required int userId, required String senha}) async {
    final r = await api.login(empresaId: empresaId, userId: userId, senha: senha);
    final user = r['user'] as Map<String, dynamic>;
    final empresa = r['empresa'] as Map<String, dynamic>;
    final novaEmpresa = (empresa['id'] as num).toInt();

    if (novaEmpresa != config.empresaId) {
      config.catalogoVersao = '';
    }
    config.token = '${r['token']}';
    config.userId = (user['id'] as num).toInt();
    config.userName = '${user['name']}';
    config.empresaId = novaEmpresa;
    config.empresaNome = '${empresa['nome'] ?? ''}';
    config.qtdMesas = (empresa['qtd_mesas'] as num?)?.toInt() ?? 20;
    await config.save();

    sync.liberarSessao();
    etapa = Etapa.mesas;
    notifyListeners();
    sync.iniciar();
    await sync.atualizarCatalogo();
    sync.agora(forcarMesas: true);
  }

  /// Os pedidos pendentes continuam no celular e saem no próximo login.
  Future<void> sair() async {
    await api.logout();
    config.clearSession();
    await config.save();
    sync.pausar();
    etapa = Etapa.login;
    notifyListeners();
  }

  /// Mantém aparelho (uuid), último endereço e os pedidos pendentes no celular.
  Future<void> trocarServidor() async {
    sync.pausar();
    config.clearSession();
    config.baseUrl = '';
    config.deviceApproved = false;
    config.catalogoVersao = '';
    await config.save();
    etapa = Etapa.conectar;
    notifyListeners();
  }

  void _onSessaoRecusada() {
    final e = sync.sessaoRecusada.value;
    if (e == null) return;
    sync.pausar();
    config.clearSession();
    if (e.aparelhoBloqueado) {
      // Revogado/excluído no ERP: bloqueia. Outros 403 não apagam a aprovação local.
      if (e.code == 'device_revoked') {
        config.deviceApproved = false;
        etapa = Etapa.aguardandoAprovacao;
      } else if (e.code == 'device_not_approved' || e.code == 'device_required') {
        // Confirma no servidor antes de jogar o garçom de volta na fila
        // (evita pedir autorização de novo só porque a sessão caiu).
        _confirmarBloqueioAparelho();
        return;
      } else {
        etapa = Etapa.login;
      }
    } else {
      etapa = Etapa.login;
    }
    config.save();
    notifyListeners();
  }

  Future<void> _confirmarBloqueioAparelho() async {
    try {
      final ok = await verificarAprovacao();
      if (ok) {
        etapa = Etapa.login;
      } else {
        config.deviceApproved = false;
        etapa = Etapa.aguardandoAprovacao;
      }
    } catch (_) {
      // Sem rede: mantém aprovação local e só pede login de novo.
      etapa = config.deviceApproved ? Etapa.login : Etapa.aguardandoAprovacao;
    }
    await config.save();
    notifyListeners();
  }
}
