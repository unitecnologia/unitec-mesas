import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import 'config.dart';

export '../app_info.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code, this.retry = false, this.detalhes});

  final String message;

  /// null = não chegou ao servidor (sem rede, timeout).
  final int? statusCode;
  final String? code;
  final bool retry;
  final Map<String, dynamic>? detalhes;

  bool get semConexao => statusCode == null;

  bool get aparelhoBloqueado =>
      code == 'device_not_approved' || code == 'device_revoked' || code == 'device_required';

  bool get sessaoInvalida =>
      statusCode == 401 || code == 'session_invalid' || code == 'access_denied' || aparelhoBloqueado;

  @override
  String toString() => message;
}

/// Cliente da API do Unitec Mesas (`/api/v1/mesas`). O celular nunca acessa o banco.
class Api {
  Api(this.config);

  final AppConfig config;
  final http.Client _http = http.Client();

  static const _curto = Duration(seconds: 8);
  static const _medio = Duration(seconds: 15);
  static const _longo = Duration(seconds: 60);

  Map<String, String> _headers({bool auth = false}) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (config.deviceUuid.isNotEmpty) 'X-MES-Device': config.deviceUuid,
        if (auth && config.token.isNotEmpty) 'Authorization': 'Bearer ${config.token}',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${config.apiBase}/$path').replace(queryParameters: query);

  static Future<bool> pingBase(String baseUrl, {Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/api/v1/mesas/ping'), headers: {'Accept': 'application/json'})
          .timeout(timeout);
      if (r.statusCode != 200) return false;
      final body = jsonDecode(r.body);
      return body is Map && body['app'] == 'unitec-mesas';
    } catch (_) {
      return false;
    }
  }

  Future<bool> ping() => pingBase(config.baseUrl);

  Future<Map<String, dynamic>> registrarAparelho() => _send(
        () => _http.post(_uri('devices/register'),
            headers: _headers(),
            body: jsonEncode({
              'device_uuid': config.deviceUuid,
              'device_name': config.deviceName,
              'platform': 'android',
              'app_version': kAppVersion,
            })),
        _medio,
      );

  Future<Map<String, dynamic>> statusAparelho() => _send(
        () => _http.get(_uri('devices/status', {'device_uuid': config.deviceUuid}), headers: _headers()),
        _curto,
      );

  Future<Map<String, dynamic>> info() => _send(() => _http.get(_uri('info'), headers: _headers()), _medio);

  Future<List<dynamic>> usuarios(int empresaId) async {
    final data = await _send(
      () => _http.get(_uri('users', {'empresa_id': '$empresaId'}), headers: _headers()),
      _medio,
    );
    return data['users'] as List<dynamic>? ?? const [];
  }

  Future<Map<String, dynamic>> login({required int empresaId, required int userId, required String senha}) =>
      _send(
        () => _http.post(_uri('auth/login'),
            headers: _headers(),
            body: jsonEncode({
              'empresa_id': empresaId,
              'user_id': userId,
              'senha': senha,
              'device_uuid': config.deviceUuid,
              'device_name': config.deviceName,
              'platform': 'android',
              'app_version': kAppVersion,
            })),
        _medio,
      );

  Future<void> logout() async {
    try {
      await _http.post(_uri('auth/logout'), headers: _headers(auth: true)).timeout(_curto);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> me() => _send(() => _http.get(_uri('auth/me'), headers: _headers(auth: true)), _curto);

  Future<Map<String, dynamic>> catalogo(String versao) => _send(
        () => _http.get(_uri('catalogo', {'versao': versao}), headers: _headers(auth: true)),
        _longo,
      );

  Future<Map<String, dynamic>> mesas(String assinatura) => _send(
        () => _http.get(_uri('mesas', {'s': assinatura}), headers: _headers(auth: true)),
        _curto,
      );

  Future<Map<String, dynamic>> comanda(int numero) =>
      _send(() => _http.get(_uri('mesas/$numero'), headers: _headers(auth: true)), _medio);

  Future<Map<String, dynamic>> lancar(Map<String, dynamic> corpo) => _send(
        () => _http.post(_uri('lancamentos'), headers: _headers(auth: true), body: jsonEncode(corpo)),
        _medio,
      );

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request, Duration timeout) async {
    if (config.baseUrl.isEmpty) {
      throw ApiException('Servidor não configurado.');
    }

    final http.Response r;
    try {
      r = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('Servidor não respondeu a tempo.');
    } on SocketException {
      throw ApiException('Sem conexão com o servidor.');
    } on http.ClientException {
      throw ApiException('Sem conexão com o servidor.');
    } on HandshakeException {
      throw ApiException('Falha de segurança na conexão (HTTPS).');
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (r.statusCode >= 200 && r.statusCode < 300) {
      return body ?? <String, dynamic>{};
    }

    final erros = body?['errors'];
    final errosTxt = erros is Map ? erros.values.expand((v) => v is List ? v : [v]).join(' ') : null;
    final message = (body?['message'] ?? errosTxt ?? body?['exception'] ?? 'Erro HTTP ${r.statusCode}').toString().trim();
    final code = body?['code']?.toString();
    final exception = body?['exception']?.toString();

    // Texto legível na fila de pedidos (código + HTTP + detalhe do servidor).
    final partes = <String>[
      if (code != null && code.isNotEmpty) code,
      'HTTP ${r.statusCode}',
      if (message.isNotEmpty) message,
      if (exception != null &&
          exception.isNotEmpty &&
          !message.toLowerCase().contains(exception.toLowerCase()))
        exception,
    ];

    throw ApiException(
      partes.join(' · '),
      statusCode: r.statusCode,
      code: code,
      retry: body?['retry'] == true || r.statusCode >= 500 || r.statusCode == 429,
      detalhes: body?['detalhes'] is Map<String, dynamic> ? body!['detalhes'] as Map<String, dynamic> : null,
    );
  }
}
