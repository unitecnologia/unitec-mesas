import 'dart:io';

import 'api.dart';

/// Procura o ERP na rede Wi-Fi (portas 8765 produção / 8000 desenvolvimento).
class DescobertaServidor {
  static const portas = [8765, 8000];
  static const _lote = 16;

  static Future<String?> procurar({void Function(int feito, int total)? progresso}) async {
    final prefixos = <String>{};
    try {
      for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in iface.addresses) {
          final p = a.address.split('.');
          if (p.length == 4 && _privado(a.address)) prefixos.add('${p[0]}.${p[1]}.${p[2]}');
        }
      }
    } catch (_) {}

    for (final prefixo in prefixos) {
      for (var inicio = 1; inicio <= 254; inicio += _lote) {
        final fim = (inicio + _lote - 1).clamp(1, 254);
        final r = await Future.wait([for (var h = inicio; h <= fim; h++) _testar('$prefixo.$h')]);
        progresso?.call(fim, 254);
        for (final base in r) {
          if (base != null) return base;
        }
      }
    }
    return null;
  }

  static bool _privado(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
    final b = int.tryParse(m?.group(1) ?? '') ?? 0;
    return b >= 16 && b <= 31;
  }

  static Future<String?> _testar(String ip) async {
    for (final porta in portas) {
      try {
        final s = await Socket.connect(ip, porta, timeout: const Duration(milliseconds: 500));
        s.destroy();
      } catch (_) {
        continue;
      }
      final base = 'http://$ip:$porta';
      if (await Api.pingBase(base, timeout: const Duration(seconds: 2))) return base;
    }
    return null;
  }
}
