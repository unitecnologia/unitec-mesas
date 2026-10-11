/// Normaliza o endereço do ERP digitado pelo usuário.
/// IP da rede local: http + porta 8765 (produção no cliente) quando omitida.
/// Túnel / domínio público: https sem porta.
class ErpUrl {
  static const hostsNuvem = ['trycloudflare.com', 'cfargotunnel.com', 'unierp.uk'];

  static const int portaLocalPadrao = 8765;

  static String normalize(String raw, {int defaultPort = portaLocalPadrao}) {
    var texto = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (texto.isEmpty) return '';

    if (!texto.contains('://')) {
      final host = texto.split('/').first.split(':').first;
      texto = '${_ehLocal(host) ? 'http' : 'https'}://$texto';
    }

    final uri = Uri.tryParse(texto);
    if (uri == null || uri.host.isEmpty) return texto;

    final publico = !_ehLocal(uri.host);
    var scheme = uri.scheme;
    int? port = uri.hasPort ? uri.port : null;

    if (publico) {
      scheme = 'https';
      if (port != null && port != 443) port = null;
    } else {
      port ??= defaultPort;
      if (scheme != 'http' && scheme != 'https') scheme = 'http';
    }

    return Uri(scheme: scheme, host: uri.host, port: port, path: uri.path)
        .toString()
        .replaceAll(RegExp(r'/+$'), '');
  }

  static bool _ehLocal(String host) {
    final h = host.toLowerCase();
    for (final dominio in hostsNuvem) {
      if (h == dominio || h.endsWith('.$dominio')) return false;
    }
    if (h == 'localhost' || h == '127.0.0.1' || h == '10.0.2.2') return true;
    final p = h.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]);
    final b = int.tryParse(p[1]);
    if (a == null || b == null) return false;
    return a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }
}
