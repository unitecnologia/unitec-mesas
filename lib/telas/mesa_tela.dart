import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/app_state.dart';
import '../core/formato.dart';
import '../core/modelos.dart';
import 'item_sheet.dart';
import 'tab_preco_sheet.dart';
import 'widgets.dart';

class MesaTela extends StatefulWidget {
  const MesaTela({super.key, required this.state, required this.numero, this.mesa});

  final AppState state;
  final int numero;
  final MesaInfo? mesa;

  @override
  State<MesaTela> createState() => _MesaTelaState();
}

class _MesaTelaState extends State<MesaTela> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _busca = TextEditingController();
  Timer? _debounce;

  List<Produto> _resultados = [];
  List<ItemPedido> _itens = [];
  String? _abertaEmVista;
  bool _rascunhoCarregado = false;

  Map<String, dynamic>? _comanda;
  DateTime? _comandaEm;
  bool _carregandoComanda = false;
  List<Pedido> _pedidosLocais = [];

  AppState get _st => widget.state;

  @override
  void initState() {
    super.initState();
    _iniciar();
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_tabs.indexIsChanging) _carregarComanda();
    });
    _st.sync.versaoDados.addListener(_recarregarPedidos);
  }

  @override
  void dispose() {
    _st.sync.versaoDados.removeListener(_recarregarPedidos);
    _debounce?.cancel();
    _busca.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final rascunho = await _st.db.rascunho(widget.numero);
    final mesa = (await _st.db.mesas())[widget.numero] ?? widget.mesa;
    if (rascunho != null) {
      _itens = rascunho.$1;
      _abertaEmVista = rascunho.$2;
    } else {
      // Data de abertura que o garçom está vendo: se a mesa fechar até o envio, o servidor avisa.
      _abertaEmVista = (mesa?.qtd ?? 0) > 0 ? mesa?.abertaEm : null;
    }
    final cache = await _st.db.comanda(widget.numero);
    if (cache != null) {
      _comanda = cache.$1;
      _comandaEm = cache.$2;
    }
    _rascunhoCarregado = true;
    await _pesquisar('');
    await _recarregarPedidos();
  }

  Future<void> _recarregarPedidos() async {
    final lista = await _st.db.pedidos(numero: widget.numero);
    if (mounted) setState(() => _pedidosLocais = lista);
  }

  void _onBusca(String texto) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _pesquisar(texto));
  }

  Future<void> _pesquisar(String texto) async {
    final r = await _st.db.buscarProdutos(texto);
    if (mounted) setState(() => _resultados = r);
  }

  Future<void> _salvarRascunho() async {
    if (!_rascunhoCarregado) return;
    await _st.db.salvarRascunho(widget.numero, _itens, _abertaEmVista);
  }

  Future<void> _adicionar(Produto p) async {
    double? precoOverride;
    String? nivel;

    FocusManager.instance.primaryFocus?.unfocus();

    final tab = await _st.db.tabPrecoDoProduto(p.id);
    if (!mounted) return;
    if (tab != null && tab.ativo) {
      final escolha = await mostrarTabPrecoSheet(
        context,
        produtoNome: p.descricao,
        info: tab,
      );
      if (escolha == null || !mounted) return;
      precoOverride = escolha.preco;
      nivel = escolha.nivel;
    }

    final item = await mostrarItemSheet(
      context,
      produto: p,
      precoOverride: precoOverride,
      nivel: nivel,
    );
    if (item == null) return;
    setState(() {
      final igual = _itens.where((i) =>
          i.productId == item.productId &&
          i.obs == item.obs &&
          i.preco == item.preco &&
          i.nivel == item.nivel);
      if (igual.isNotEmpty) {
        igual.first.quantidade = double.parse((igual.first.quantidade + item.quantidade).toStringAsFixed(3));
      } else {
        _itens.add(item);
      }
    });
    await _salvarRascunho();
    if (mounted) avisar(context, '${quantidade(item.quantidade)} × ${item.descricao}');
  }

  double get _total => _itens.fold(0.0, (s, i) => s + i.total);

  Future<void> _revisar() async {
    final enviar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CarrinhoSheet(
        numero: widget.numero,
        itens: _itens,
        onAlterado: () {
          setState(() {});
          _salvarRascunho();
        },
      ),
    );
    if (enviar == true) await _enviar();
  }

  Future<void> _enviar() async {
    if (_itens.isEmpty) return;
    final pedido = Pedido(
      uuid: const Uuid().v4(),
      numero: widget.numero,
      itens: List.of(_itens),
      status: StatusPedido.pendente,
      criadoEm: DateTime.now(),
      abertaEmVista: _abertaEmVista,
    );
    // Grava no celular antes de qualquer envio: queda de Wi-Fi não perde o pedido.
    await _st.db.criarPedido(pedido);
    await _st.sync.atualizarContadores();
    _st.sync.agora();
    if (!mounted) return;
    avisar(context, _st.sync.online == true
        ? 'Pedido da ${rotuloMesa(widget.numero)} salvo. Enviando ao PDV…'
        : 'Sem conexão: pedido guardado e será enviado quando a conexão voltar.');
    Navigator.of(context).pop();
  }

  Future<void> _carregarComanda() async {
    if (_carregandoComanda) return;
    setState(() => _carregandoComanda = true);
    final r = await _st.sync.buscarComanda(widget.numero);
    if (!mounted) return;
    setState(() {
      _carregandoComanda = false;
      if (r != null) {
        _comanda = r;
        _comandaEm = DateTime.now();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final situacao = (_comanda?['situacao'] as num?)?.toInt() ?? widget.mesa?.situacao ?? SituacaoMesa.livre;

    return Scaffold(
        appBar: AppBar(
          title: Text(rotuloMesa(widget.numero), style: const TextStyle(fontWeight: FontWeight.w700)),
          actions: [StatusConexao(sync: _st.sync), const SizedBox(width: 6)],
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Lançar'), Tab(text: 'Comanda')]),
        ),
        body: Column(children: [
          if (situacao == SituacaoMesa.aguardandoFechamento)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEF3C7),
              padding: const EdgeInsets.all(8),
              child: const Text(
                'Mesa aguardando fechamento (pré-conta impressa). Novos itens só entram depois que o caixa reabrir a mesa.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              _lancar(cs),
              _comandaView(cs),
            ]),
          ),
        ]),
        bottomNavigationBar: _itens.isEmpty
            ? null
            : SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(top: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: _revisar,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('${_itens.length} ${_itens.length == 1 ? 'item' : 'itens'} no pedido',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          Text(moeda(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _revisar,
                      icon: const Icon(Icons.send),
                      label: const Text('Revisar e enviar'),
                    ),
                  ]),
                ),
              ),
    );
  }

  Widget _lancar(ColorScheme cs) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: TextField(
          controller: _busca,
          onChanged: _onBusca,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar produto (nome ou código)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _busca.clear();
                _pesquisar('');
              },
            ),
          ),
        ),
      ),
      Expanded(
        child: _resultados.isEmpty
            ? Center(child: Text('Nenhum produto encontrado.', style: TextStyle(color: cs.onSurfaceVariant)))
            : ListView.separated(
                itemCount: _resultados.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = _resultados[i];
                  return ListTile(
                    dense: true,
                    title: Text(p.descricao, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${p.codigo}${p.grupo.isNotEmpty ? ' · ${p.grupo}' : ''}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: Text(
                      '${moeda(p.preco)}${p.pesado ? '/${p.unidade}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _adicionar(p),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _comandaView(ColorScheme cs) {
    final itens = (_comanda?['itens'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final total = (_comanda?['total'] as num?)?.toDouble() ?? 0;
    final naoEnviados = _pedidosLocais.where((p) => p.status != StatusPedido.enviado).toList();

    return RefreshIndicator(
      onRefresh: _carregarComanda,
      child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        if (naoEnviados.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text('Ainda não confirmados pelo PDV',
                style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          ),
          for (final p in naoEnviados)
            ListTile(
              dense: true,
              title: Text('${p.itens.length} item(ns) · ${moeda(p.total)}'),
              subtitle: Text(p.erroMsg ?? 'Feito às ${hora(p.criadoEm)}', maxLines: 2),
              trailing: SeloPedido(status: p.status),
            ),
          const Divider(),
        ],
        ListTile(
          dense: true,
          title: const Text('Comanda no PDV', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_comandaEm == null
              ? 'Ainda não consultada'
              : 'Atualizada às ${hora(_comandaEm)}${_st.sync.online == false ? ' (offline)' : ''}'),
          trailing: _carregandoComanda
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(icon: const Icon(Icons.refresh), onPressed: _carregarComanda),
        ),
        if (itens.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Mesa sem itens no PDV.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        for (final it in itens)
          ListTile(
            dense: true,
            title: Text('${quantidade((it['quantidade'] as num).toDouble())} × ${it['descricao']}'),
            subtitle: () {
              final nivel = '${it['tabela_nivel'] ?? it['nivel'] ?? ''}'.trim();
              final obs = '${it['obs'] ?? ''}'.trim();
              final parts = <String>[
                if (nivel.isNotEmpty) nivel.toUpperCase(),
                if (obs.isNotEmpty) 'Obs: $obs',
              ];
              if (parts.isEmpty) return null;
              return Text(
                parts.join(' · '),
                style: obs.isNotEmpty ? const TextStyle(color: Color(0xFFB45309)) : null,
              );
            }(),
            trailing: Text(moeda((it['total'] as num).toDouble())),
          ),
        if (itens.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
              Text(moeda(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Fechamento, pagamento e cupom fiscal são feitos no PDV.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}

class _CarrinhoSheet extends StatefulWidget {
  const _CarrinhoSheet({required this.numero, required this.itens, required this.onAlterado});

  final int numero;
  final List<ItemPedido> itens;
  final VoidCallback onAlterado;

  @override
  State<_CarrinhoSheet> createState() => _CarrinhoSheetState();
}

class _CarrinhoSheetState extends State<_CarrinhoSheet> {
  void _alterar(VoidCallback fn) {
    setState(fn);
    widget.onAlterado();
  }

  @override
  Widget build(BuildContext context) {
    final itens = widget.itens;
    final total = itens.fold(0.0, (s, i) => s + i.total);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Text('Pedido · ${rotuloMesa(widget.numero)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Text(moeda(total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: itens.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = itens[i];
                return ListTile(
                  dense: true,
                  title: Text(it.descricao, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${quantidade(it.quantidade)} ${it.unidade} × ${moeda(it.preco)}'
                    '${it.nivel != null ? ' · ${it.nivel!.toUpperCase()}' : ''}'
                    '${it.obs.isNotEmpty ? '\nObs: ${it.obs}' : ''}',
                  ),
                  isThreeLine: it.obs.isNotEmpty,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(moeda(it.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () async {
                        final novo = await mostrarItemSheet(
                          context,
                          item: it,
                          precoOverride: it.preco,
                          nivel: it.nivel,
                        );
                        if (novo != null) {
                          _alterar(() {
                            it.quantidade = novo.quantidade;
                            it.obs = novo.obs;
                          });
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                      onPressed: () => _alterar(() => itens.removeAt(i)),
                    ),
                  ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: itens.isEmpty ? null : () => Navigator.pop(context, true),
                icon: const Icon(Icons.send),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Enviar pedido ao PDV'),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
