import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/modelos.dart';

/// Quantidade + observação de um item. Novo (produto) ou edição (item).
Future<ItemPedido?> mostrarItemSheet(
  BuildContext context, {
  Produto? produto,
  ItemPedido? item,
  double? precoOverride,
  String? nivel,
}) {
  return showModalBottomSheet<ItemPedido>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ItemSheet(
        produto: produto,
        item: item,
        precoOverride: precoOverride,
        nivel: nivel ?? item?.nivel,
      ),
    ),
  );
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({this.produto, this.item, this.precoOverride, this.nivel});

  final Produto? produto;
  final ItemPedido? item;
  final double? precoOverride;
  final String? nivel;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late double _qtd = widget.item?.quantidade ?? 1;
  late final _obs = TextEditingController(text: widget.item?.obs ?? '');
  late final _qtdTexto = TextEditingController(text: quantidade(_qtd));

  bool get _pesado => widget.produto?.pesado ?? widget.item?.pesado ?? false;
  String get _descricao => widget.produto?.descricao ?? widget.item!.descricao;
  String get _unidade => widget.produto?.unidade ?? widget.item!.unidade;
  double get _preco => widget.precoOverride ?? widget.item?.preco ?? widget.produto?.preco ?? 0;

  @override
  void dispose() {
    _obs.dispose();
    _qtdTexto.dispose();
    super.dispose();
  }

  void _passo(int delta) {
    setState(() {
      _qtd = (_qtd + delta).clamp(1, 999).toDouble();
      _qtdTexto.text = quantidade(_qtd);
    });
  }

  void _confirmar() {
    final qtd = _pesado ? (parseDecimal(_qtdTexto.text) ?? 0) : _qtd;
    if (qtd <= 0 || qtd > 9999) return;
    final obs = _obs.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    Navigator.pop(
      context,
      ItemPedido(
        productId: widget.produto?.id ?? widget.item!.productId,
        descricao: _descricao,
        unidade: _unidade,
        quantidade: double.parse(qtd.toStringAsFixed(3)),
        preco: _preco,
        obs: obs.length > 140 ? obs.substring(0, 140) : obs,
        pesado: _pesado,
        nivel: widget.nivel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qtdAtual = _pesado ? (parseDecimal(_qtdTexto.text) ?? 0) : _qtd;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_descricao, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(
            '${moeda(_preco)} / $_unidade'
            '${widget.nivel != null ? ' · ${widget.nivel!.toUpperCase()}' : ''}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          if (_pesado)
            TextField(
              controller: _qtdTexto,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantidade ($_unidade)', hintText: '0,350'),
              onChanged: (_) => setState(() {}),
            )
          else
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(
                  onPressed: _qtd > 1 ? () => _passo(-1) : null, icon: const Icon(Icons.remove), iconSize: 28),
              SizedBox(
                width: 80,
                child: Text(quantidade(_qtd),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              ),
              IconButton.filledTonal(onPressed: () => _passo(1), icon: const Icon(Icons.add), iconSize: 28),
            ]),
          const SizedBox(height: 12),
          TextField(
            controller: _obs,
            maxLength: 140,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observação (opcional)',
              hintText: 'Ex.: sem cebola, bem passado',
              counterText: '',
            ),
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: qtdAtual > 0 ? _confirmar : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(widget.item == null
                  ? 'Adicionar · ${moeda(qtdAtual * _preco)}'
                  : 'Salvar · ${moeda(qtdAtual * _preco)}'),
            ),
          ),
        ]),
      ),
    );
  }
}
