import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';

/// Versão publicada na GitHub Release, com os assets do APK e do SHA-256.
class AppRelease {
  AppRelease({
    required this.tag,
    required this.versionName,
    required this.versionCode,
    required this.apkName,
    required this.apkUrl,
    required this.apkSize,
    required this.sha256Url,
  });

  final String tag;
  final String versionName;

  /// versionCode declarado nas notas da Release (null se não informado).
  final int? versionCode;
  final String apkName;
  final String apkUrl;
  final int apkSize;
  final String sha256Url;
}

class AtualizacaoException implements Exception {
  AtualizacaoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Atualização do APK pela GitHub Release pública do Unitec Mesas (sem token).
///
/// Só troca o APK: não toca em SQLite, sessão, configuração nem pedidos pendentes.
/// O instalador do Android exige a mesma assinatura e a confirmação do usuário.
class AppUpdater {
  AppUpdater._();

  static final AppUpdater instance = AppUpdater._();

  static const _repo = 'unitecnologia/unitec-mesas';
  // MESAS_UPDATE_URL só existe em build de teste local (sem o intervalo mínimo).
  static const _buildTeste = bool.hasEnvironment('MESAS_UPDATE_URL');
  static const _latestUrl = String.fromEnvironment(
    'MESAS_UPDATE_URL',
    defaultValue: 'https://api.github.com/repos/$_repo/releases/latest',
  );
  static const _userAgent = 'unitec-mesas/$kAppVersion+$kAppBuild';
  static const _prefUltimaConsulta = 'update_ultima_consulta_ms';
  // Vários celulares na mesma rede dividem o limite anônimo da API do GitHub.
  static const _intervalo = Duration(hours: 6);
  static const _channel = MethodChannel('br.com.unitec.unitec_mesas/updater');

  static const msgInvalido = 'Não foi possível validar o arquivo de atualização.';

  Future<String>? _downloadEmAndamento;
  http.Client? _client;
  bool _cancelado = false;

  bool get baixando => _downloadEmAndamento != null;

  /// Release mais nova que a instalada, ou null (já atualizado, offline, falha).
  /// Sem [forcar], consulta no máximo uma vez a cada [_intervalo]. Nunca lança.
  Future<AppRelease?> verificar({bool forcar = false}) async {
    if (!Platform.isAndroid) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ultima = prefs.getInt(_prefUltimaConsulta) ?? 0;
      final agora = DateTime.now().millisecondsSinceEpoch;
      if (!forcar && !_buildTeste && agora >= ultima && agora - ultima < _intervalo.inMilliseconds) {
        return null;
      }
      if (!baixando) await _limparDownloadsAntigos();

      final r = await http.get(Uri.parse(_latestUrl), headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': _userAgent,
      }).timeout(const Duration(seconds: 8));
      // Resposta do GitHub (mesmo sem release) conta como consulta feita;
      // falha de rede não conta, para tentar de novo na próxima abertura.
      if (r.statusCode == 200 || r.statusCode == 404) {
        await prefs.setInt(_prefUltimaConsulta, agora);
      }
      if (r.statusCode != 200) return null;

      final release = parseRelease(jsonDecode(r.body));
      if (release == null || !ehMaisNova(release)) return null;
      return release;
    } catch (e) {
      debugPrint('Atualização: consulta ignorada ($e)');
      return null;
    }
  }

  /// JSON de `releases/latest` → release instalável (exige APK + `.sha256`).
  static AppRelease? parseRelease(dynamic data) {
    if (data is! Map) return null;
    if (data['draft'] == true || data['prerelease'] == true) return null;
    final tag = (data['tag_name'] ?? '').toString().trim();
    final versionName = tag.startsWith('v') ? tag.substring(1) : tag;
    if (versionName.isEmpty) return null;

    final assets = (data['assets'] as List? ?? []).whereType<Map>().toList();
    Map? apk;
    for (final a in assets) {
      if ((a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        apk = a;
        break;
      }
    }
    if (apk == null) return null;
    final apkName = apk['name'].toString();
    Map? sha;
    for (final a in assets) {
      if ((a['name'] ?? '').toString() == '$apkName.sha256') {
        sha = a;
        break;
      }
    }
    // Sem SHA-256 publicado não há como validar o arquivo: não oferece.
    if (sha == null) return null;

    final body = (data['body'] ?? '').toString();
    final match = RegExp(r'versionCode\s*(\d+)', caseSensitive: false).firstMatch(body);
    return AppRelease(
      tag: tag,
      versionName: versionName,
      versionCode: match == null ? null : int.tryParse(match.group(1)!),
      apkName: apkName,
      apkUrl: (apk['browser_download_url'] ?? '').toString(),
      apkSize: apk['size'] is int ? apk['size'] as int : 0,
      sha256Url: (sha['browser_download_url'] ?? '').toString(),
    );
  }

  /// versionCode manda; sem ele, compara o nome X.Y.Z.
  static bool ehMaisNova(AppRelease r, {int build = kAppBuild, String versao = kAppVersion}) {
    final code = r.versionCode;
    if (code != null) return code > build;
    return compararVersao(r.versionName, versao) > 0;
  }

  static int compararVersao(String a, String b) {
    List<int> partes(String v) => v.split(RegExp(r'[.+-]')).map((s) => int.tryParse(s) ?? 0).toList();
    final pa = partes(a);
    final pb = partes(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  Future<Directory> _pasta() async {
    final cache = await getTemporaryDirectory();
    return Directory(p.join(cache.path, 'atualizacao'));
  }

  Future<void> _limparDownloadsAntigos() async {
    try {
      final dir = await _pasta();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Baixa e valida o APK. Retorna o caminho do arquivo pronto para instalar.
  /// Chamadas simultâneas reaproveitam o mesmo download.
  Future<String> baixar(AppRelease release, {void Function(int recebido, int total)? progresso}) {
    final atual = _downloadEmAndamento;
    if (atual != null) return atual;
    _cancelado = false;
    final f = _baixar(release, progresso);
    _downloadEmAndamento = f;
    return f.whenComplete(() => _downloadEmAndamento = null);
  }

  /// Interrompe o download (o app segue normalmente; nada é instalado).
  void cancelar() {
    _cancelado = true;
    _client?.close();
  }

  Future<String> _baixar(AppRelease release, void Function(int, int)? progresso) async {
    final dir = await _pasta();
    await dir.create(recursive: true);
    final destino = File(p.join(dir.path, release.apkName));
    final parcial = File('${destino.path}.part');
    final client = http.Client();
    _client = client;
    try {
      for (final f in [destino, parcial]) {
        if (await f.exists()) await f.delete();
      }

      final shaResp = await client
          .get(Uri.parse(release.sha256Url), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
      if (shaResp.statusCode != 200) {
        throw AtualizacaoException('Não foi possível baixar a atualização (HTTP ${shaResp.statusCode}).');
      }
      final esperado = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(shaResp.body)?.group(0)?.toLowerCase();
      if (esperado == null) throw AtualizacaoException(msgInvalido);

      final req = http.Request('GET', Uri.parse(release.apkUrl))..headers['User-Agent'] = _userAgent;
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw AtualizacaoException('Não foi possível baixar a atualização (HTTP ${resp.statusCode}).');
      }
      final total = resp.contentLength ?? release.apkSize;
      var recebido = 0;
      var ultimoAviso = 0;
      final sink = parcial.openWrite();
      try {
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          recebido += chunk.length;
          // Avisa a tela a cada ~256 KB: menos redesenho em celular fraco.
          if (recebido - ultimoAviso >= 262144 || recebido == total) {
            ultimoAviso = recebido;
            progresso?.call(recebido, total);
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && recebido != total) {
        throw AtualizacaoException('Download incompleto. Tente novamente.');
      }

      final calculado = (await sha256.bind(parcial.openRead()).first).toString();
      if (calculado != esperado) throw AtualizacaoException(msgInvalido);
      await parcial.rename(destino.path);
      await _conferirPacote(destino.path);
      return destino.path;
    } catch (e) {
      for (final f in [destino, parcial]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (_cancelado) throw AtualizacaoException('Download cancelado.');
      if (e is AtualizacaoException) rethrow;
      if (e is TimeoutException) {
        throw AtualizacaoException('Tempo esgotado ao baixar a atualização. Tente novamente.');
      }
      if (e is SocketException || e is http.ClientException) {
        throw AtualizacaoException('Sem conexão para baixar a atualização. Tente novamente.');
      }
      if (e is PlatformException) throw AtualizacaoException(msgInvalido);
      throw AtualizacaoException('Não foi possível baixar a atualização. Tente novamente.');
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  /// O arquivo precisa ser deste app e mais novo que o instalado.
  Future<void> _conferirPacote(String path) async {
    final info = await _channel.invokeMapMethod<String, dynamic>('apkInfo', {'path': path});
    final pacote = info?['packageName']?.toString();
    final atual = info?['currentPackage']?.toString();
    final code = (info?['versionCode'] as num?)?.toInt();
    if (info == null || pacote == null || pacote != atual || code == null) {
      await File(path).delete();
      throw AtualizacaoException(msgInvalido);
    }
    if (code <= kAppBuild) {
      await File(path).delete();
      throw AtualizacaoException('O aplicativo já está na versão mais recente.');
    }
  }

  /// Android 8+: "Permitir desta fonte" liberado para este app.
  Future<bool> podeInstalar() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  Future<void> abrirPermissaoInstalacao() async {
    await _channel.invokeMethod<bool>('openInstallSettings');
  }

  /// Abre o instalador padrão do Android (o usuário confirma).
  Future<bool> instalar(String path) async =>
      await _channel.invokeMethod<bool>('installApk', {'path': path}) ?? false;
}
