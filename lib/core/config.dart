import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Conexão, aparelho e sessão do garçom, guardados no celular (abre offline).
class AppConfig {
  String baseUrl = '';

  /// Último servidor que respondeu; continua salvo ao trocar de servidor (botão Reconectar).
  String lastBaseUrl = '';
  String deviceUuid = '';
  String deviceName = '';
  String pairingCode = '';
  bool deviceApproved = false;

  String token = '';
  int userId = 0;
  String userName = '';
  int empresaId = 0;
  String empresaNome = '';
  int qtdMesas = 20;

  String catalogoVersao = '';
  String catalogoAtualizadoEm = '';

  bool get isConnected => baseUrl.isNotEmpty;

  bool get hasSession =>
      token.isNotEmpty && userId > 0 && empresaId > 0 && deviceUuid.isNotEmpty && deviceApproved;

  String get apiBase => '$baseUrl/api/v1/mesas';

  static const _key = 'unitec_mesas_config';

  /// Chaves extras: sobrevivem mesmo se o JSON principal corromper.
  /// Só somem ao desinstalar o app (comportamento desejado).
  static const _keyUuid = 'unitec_mesas_device_uuid';
  static const _keyApproved = 'unitec_mesas_device_approved';

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'lastBaseUrl': lastBaseUrl,
        'deviceUuid': deviceUuid,
        'deviceName': deviceName,
        'pairingCode': pairingCode,
        'deviceApproved': deviceApproved,
        'token': token,
        'userId': userId,
        'userName': userName,
        'empresaId': empresaId,
        'empresaNome': empresaNome,
        'qtdMesas': qtdMesas,
        'catalogoVersao': catalogoVersao,
        'catalogoAtualizadoEm': catalogoAtualizadoEm,
      };

  void _fromJson(Map<String, dynamic> j) {
    baseUrl = '${j['baseUrl'] ?? ''}';
    lastBaseUrl = '${j['lastBaseUrl'] ?? ''}';
    if (lastBaseUrl.isEmpty) lastBaseUrl = baseUrl;
    deviceUuid = '${j['deviceUuid'] ?? ''}';
    deviceName = '${j['deviceName'] ?? ''}';
    pairingCode = '${j['pairingCode'] ?? ''}';
    deviceApproved = j['deviceApproved'] == true;
    token = '${j['token'] ?? ''}';
    userId = _int(j['userId']);
    userName = '${j['userName'] ?? ''}';
    empresaId = _int(j['empresaId']);
    empresaNome = '${j['empresaNome'] ?? ''}';
    qtdMesas = _int(j['qtdMesas'], 20);
    catalogoVersao = '${j['catalogoVersao'] ?? ''}';
    catalogoAtualizadoEm = '${j['catalogoAtualizadoEm'] ?? ''}';
  }

  static int _int(Object? v, [int padrao = 0]) =>
      v is int ? v : int.tryParse('${v ?? ''}') ?? padrao;

  static Future<AppConfig> load() async {
    final config = AppConfig();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        config._fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    // Restaura identidade/aprovação se o JSON falhou ou veio incompleto.
    final uuidBackup = prefs.getString(_keyUuid) ?? '';
    if (config.deviceUuid.isEmpty && uuidBackup.isNotEmpty) {
      config.deviceUuid = uuidBackup;
    }
    if (!config.deviceApproved && prefs.getBool(_keyApproved) == true) {
      config.deviceApproved = true;
    }
    return config;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
    if (deviceUuid.isNotEmpty) {
      await prefs.setString(_keyUuid, deviceUuid);
    }
    await prefs.setBool(_keyApproved, deviceApproved);
  }

  void clearSession() {
    token = '';
    userId = 0;
    userName = '';
  }
}
