import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/modelos.dart';

/// Monta a URL completa da foto a partir do caminho relativo do ERP.
String? produtoFotoUrl(String base, String? fotoUrl) {
  final f = (fotoUrl ?? '').trim();
  if (f.isEmpty) return null;
  if (f.startsWith('http://') || f.startsWith('https://')) return f;
  final b = base.replaceFirst(RegExp(r'/+$'), '');
  final path = f.startsWith('/') ? f : '/$f';
  return '$b$path';
}

/// Card de produto na listagem da mesa (foto + descrição + preço).
/// Visual alinhado ao Força de Vendas; toque abre o lançamento existente.
class ProdutoListCard extends StatelessWidget {
  const ProdutoListCard({
    super.key,
    required this.produto,
    required this.baseUrl,
    required this.onTap,
  });

  final Produto produto;
  final String baseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foto = produtoFotoUrl(baseUrl, produto.fotoUrl);

    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0xFF0F2847).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                ),
                clipBehavior: Clip.antiAlias,
                child: foto == null
                    ? Icon(Icons.image_outlined, color: cs.onSurfaceVariant.withValues(alpha: 0.45), size: 26)
                    : Image.network(
                        foto,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant.withValues(alpha: 0.45), size: 26),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.descricao,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        height: 1.22,
                        letterSpacing: -0.2,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      produto.codigo + (produto.grupo.isNotEmpty ? ' · ${produto.grupo}' : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${moeda(produto.preco)}${produto.pesado ? '/${produto.unidade}' : ''}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
