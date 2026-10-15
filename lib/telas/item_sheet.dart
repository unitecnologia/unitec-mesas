import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/modelos.dart';

/// Quantidade + observação + composição/adicionais. Novo (produto) ou edição (item).
Future<ItemPedido?> mostrarItemSheet(
  BuildContext context, {
  Produto? produto,
  ItemPedido? item,
  double? precoOverride,
  String? nivel,
  List<CompComponente> componentes = const [],
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
        componentes: componentes,
      ),
    ),
  );
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({
    this.produto,
    this.item,
    this.precoOverride,
    this.nivel,
    this.componentes = const [],
  });

  final Produto? produto;
  final ItemPedido? item;
  final double? precoOverride;
  final String? nivel;
  final List<CompComponente> componentes;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late double _qtd = widget.item?.quantidade ?? 1;
  late final _obsManual = TextEditingController(text: (widget.item?.obs ?? '').trim());
  late final _qtdTexto = TextEditingController(text: quantidade(_qtd));

  /// Adicionais: marcados = incluídos. Base: marcados = incluídos (inverso dos removidos).
  late final Set<int> _adicionaisOn = {
    ...(widget.item?.composicaoAdicionais ?? const <int>[]),
  };
  late final Set<int> _baseOn = {
    for (final c in widget.componentes.where((e) => !e.isAdicional))
      if (!(widget.item?.composicaoRemovidos.contains(c.id) ?? false)) c.id,
  };

  bool get _pesado => widget.produto?.pesado ?? widget.item?.pesado ?? false;
  String get _descricao => widget.produto?.descricao ?? widget.item!.descricao;
  String get _unidade => widget.produto?.unidade ?? widget.item!.unidade;
  double get _precoBase => widget.precoOverride ?? widget.item?.preco ?? widget.produto?.preco ?? 0;

  List<CompComponente> get _adicionais =>
      widget.componentes.where((c) => c.isAdicional).toList(growable: false);
  List<CompComponente> get _base =>
      widget.componentes.where((c) => !c.isAdicional).toList(growable: false);

  double get _acrescimoUnitario {
    var t = 0.0;
    for (final c in _adicionais) {
      if (_adicionaisOn.contains(c.id)) t += c.valorUnitario;
    }
    return double.parse(t.toStringAsFixed(2));
  }

  double get _totalLinha {
    final qtd = _pesado ? (parseDecimal(_qtdTexto.text) ?? 0) : _qtd;
    return double.parse(((qtd * _precoBase) + (qtd * _acrescimoUnitario)).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _obsManual.dispose();
    _qtdTexto.dispose();
    super.dispose();
  }

  /// Observação = só o que o garçom digitou (SEM/ADICIONAL vão em composicaoLinhas).
  String _montarObsManual() {
    var obs = _obsManual.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (obs.length > 140) obs = obs.substring(0, 140);
    return obs;
  }

  List<String> _montarLinhasComposicao(List<int> removidos, List<int> adicionais) {
    final byId = {for (final c in widget.componentes) c.id: c};
    return [
      for (final id in removidos)
        if (byId[id] != null) 'SEM ${byId[id]!.descricao}',
      for (final id in adicionais)
        if (byId[id] != null)
          'ADICIONAL: ${byId[id]!.descricao} (+ R\$ ${decimal(byId[id]!.valorUnitario, 2)})',
    ];
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

    final removidos = [
      for (final c in _base)
        if (!_baseOn.contains(c.id)) c.id,
    ];
    final adicionais = [
      for (final c in _adicionais)
        if (_adicionaisOn.contains(c.id)) c.id,
    ];
    final acrescimo = double.parse((qtd * _acrescimoUnitario).toStringAsFixed(2));

    Navigator.pop(
      context,
      ItemPedido(
        productId: widget.produto?.id ?? widget.item!.productId,
        descricao: _descricao,
        unidade: _unidade,
        quantidade: double.parse(qtd.toStringAsFixed(3)),
        preco: _precoBase,
        obs: _montarObsManual(),
        pesado: _pesado,
        nivel: widget.nivel,
        composicaoRemovidos: removidos,
        composicaoAdicionais: adicionais,
        composicaoLinhas: _montarLinhasComposicao(removidos, adicionais),
        acrescimo: acrescimo,
      ),
    );
  }

  Widget _secaoTitulo(String titulo) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        titulo,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4),
      ),
    );
  }

  Widget _linhaComponente({
    required CompComponente c,
    required bool marcado,
    required bool adicional,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final icone = adicional
        ? (marcado ? Icons.check_circle : Icons.radio_button_unchecked)
        : (marcado ? Icons.check_circle : Icons.cancel);
    final cor = adicional
        ? (marcado ? const Color(0xFF16A34A) : cs.outline)
        : (marcado ? const Color(0xFF16A34A) : const Color(0xFFDC2626));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(icone, size: 22, color: cor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                c.descricao,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: marcado ? cs.onSurface : cs.onSurfaceVariant,
                  decoration: !adicional && !marcado ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (adicional)
              Text(
                '+ ${moeda(c.valorUnitario)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: marcado ? const Color(0xFF16A34A) : cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qtdAtual = _pesado ? (parseDecimal(_qtdTexto.text) ?? 0) : _qtd;
    final temComp = widget.componentes.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_descricao, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(
                '${moeda(_precoBase)} / $_unidade'
                '${widget.nivel != null ? ' · ${widget.nivel!.toUpperCase()}' : ''}'
                '${_acrescimoUnitario > 0 ? '  ·  +${moeda(_acrescimoUnitario)} adicionais' : ''}',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
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
              if (temComp)
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_adicionais.isNotEmpty) ...[
                          _secaoTitulo('ADICIONAIS'),
                          for (final c in _adicionais)
                            _linhaComponente(
                              c: c,
                              marcado: _adicionaisOn.contains(c.id),
                              adicional: true,
                              onTap: () => setState(() {
                                if (_adicionaisOn.contains(c.id)) {
                                  _adicionaisOn.remove(c.id);
                                } else {
                                  _adicionaisOn.add(c.id);
                                }
                              }),
                            ),
                        ],
                        if (_base.isNotEmpty) ...[
                          _secaoTitulo('COMPOSIÇÃO'),
                          for (final c in _base)
                            _linhaComponente(
                              c: c,
                              marcado: _baseOn.contains(c.id),
                              adicional: false,
                              onTap: () => setState(() {
                                if (_baseOn.contains(c.id)) {
                                  _baseOn.remove(c.id);
                                } else {
                                  _baseOn.add(c.id);
                                }
                              }),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _obsManual,
                maxLength: 140,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  hintText: 'Ex.: bem passado, ponto da carne',
                  counterText: '',
                ),
                onSubmitted: (_) => _confirmar(),
              ),
              Builder(builder: (_) {
                final preview = _montarLinhasComposicao(
                  [for (final c in _base) if (!_baseOn.contains(c.id)) c.id],
                  [for (final c in _adicionais) if (_adicionaisOn.contains(c.id)) c.id],
                );
                if (preview.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    preview.join('\n'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.25),
                  ),
                );
              }),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: qtdAtual > 0 ? _confirmar : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(widget.item == null
                      ? 'Adicionar · ${moeda(_totalLinha)}'
                      : 'Salvar · ${moeda(_totalLinha)}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
