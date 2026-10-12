import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/modelos.dart';

/// Seleção obrigatória de Tab. Preço (só níveis habilitados no produto).
Future<({String nivel, double preco})?> mostrarTabPrecoSheet(
  BuildContext context, {
  required String produtoNome,
  required TabPrecoInfo info,
  String? preferido,
}) {
  if (info.niveis.isEmpty) return Future.value(null);

  var selected = 0;
  if (preferido != null) {
    final idx = info.niveis.indexOf(preferido);
    if (idx >= 0) selected = idx;
  }

  FocusManager.instance.primaryFocus?.unfocus();

  return showModalBottomSheet<({String nivel, double preco})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _TabPrecoSheet(
        produtoNome: produtoNome,
        info: info,
        selectedIndex: selected,
      ),
    ),
  );
}

class _TabPrecoSheet extends StatefulWidget {
  const _TabPrecoSheet({
    required this.produtoNome,
    required this.info,
    required this.selectedIndex,
  });

  final String produtoNome;
  final TabPrecoInfo info;
  final int selectedIndex;

  @override
  State<_TabPrecoSheet> createState() => _TabPrecoSheetState();
}

class _TabPrecoSheetState extends State<_TabPrecoSheet> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.selectedIndex.clamp(0, widget.info.niveis.length - 1);
  }

  void _confirmar() {
    final nivel = widget.info.niveis[_index];
    Navigator.pop(context, (nivel: nivel, preco: widget.info.precoDo(nivel)));
  }

  String _label(String nivel) {
    switch (nivel) {
      case 'atacado':
        return 'ATACADO';
      case 'especial':
        return 'ESPECIAL';
      case 'varejo':
      default:
        return 'VAREJO';
    }
  }

  String _codigo(String nivel) {
    switch (nivel) {
      case 'atacado':
        return '2';
      case 'especial':
        return '3';
      case 'varejo':
      default:
        return '1';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final maxH = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tabela de Preço', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                widget.produtoNome,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                'Escolha a tabela para este produto (obrigatório).',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.info.niveis.length,
                  itemBuilder: (context, i) {
                    final nivel = widget.info.niveis[i];
                    final on = i == _index;
                    final preco = widget.info.precoDo(nivel);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: on ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHighest.withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: on ? cs.primary : cs.outlineVariant, width: on ? 1.6 : 1),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _index = i),
                          onDoubleTap: () {
                            setState(() => _index = i);
                            _confirmar();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    _codigo(nivel),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: on ? cs.primary : cs.onSurface,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _label(nivel),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: on ? cs.primary : cs.onSurface,
                                    ),
                                  ),
                                ),
                                Text(
                                  moeda(preco),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: on ? cs.primary : cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              FilledButton(
                onPressed: _confirmar,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Confirmar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
