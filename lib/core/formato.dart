/// Formatação leve (sem pacote intl) para não pesar no celular.
String moeda(num valor) => 'R\$ ${decimal(valor, 2)}';

String decimal(num valor, int casas) {
  final negativo = valor < 0;
  final partes = valor.abs().toStringAsFixed(casas).split('.');
  final inteiro = partes[0];
  final buf = StringBuffer();
  for (var i = 0; i < inteiro.length; i++) {
    if (i > 0 && (inteiro.length - i) % 3 == 0) buf.write('.');
    buf.write(inteiro[i]);
  }
  final dec = partes.length > 1 ? ',${partes[1]}' : '';
  return '${negativo ? '-' : ''}$buf$dec';
}

/// Quantidade sem casas quando inteira (2), senão até 3 casas (0,350).
String quantidade(num valor) {
  if (valor == valor.roundToDouble()) return valor.toInt().toString();
  return decimal(valor, 3).replaceAll(RegExp(r',?0+$'), '');
}

String rotuloMesa(int numero) => 'Mesa ${numero.toString().padLeft(2, '0')}';

String hora(DateTime? dt) {
  if (dt == null) return '--:--';
  String d2(int v) => v.toString().padLeft(2, '0');
  return '${d2(dt.hour)}:${d2(dt.minute)}';
}

double? parseDecimal(String texto) {
  final t = texto.trim().replaceAll('.', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Texto de busca: maiúsculo e sem acento.
String normalizarBusca(String texto) {
  const de = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  const para = 'AAAAAEEEEIIIIOOOOOUUUUCN';
  final up = texto.toUpperCase();
  final buf = StringBuffer();
  for (final r in up.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    buf.write(i >= 0 ? para[i] : c);
  }
  return buf.toString().trim();
}
