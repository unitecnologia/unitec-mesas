import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/formato.dart';
import '../core/modelos.dart';
import 'widgets.dart';

/// Pedidos do celular: pendentes, com erro (aguardando decisão) e enviados recentes.
class PedidosTela extends StatefulWidget {
  const PedidosTela({super.key, required this.state});

  final AppState state;

  @override
  State<PedidosTela> createState() => _PedidosTelaState();
}

class _PedidosTelaState extends State<PedidosTela> {
  List<Pedido> _pedidos = [];

  AppState get _st => widget.state;

  @override
  void initState() {
    super.initState();
    _st.sync.versaoDados.addListener(_recarregar);
    _recarregar();
  }

  @override
  void dispose() {
    _st.sync.versaoDados.removeListener(_recarregar);
    super.dispose();
  }

  Future<void> _recarregar() async {
    final lista = await _st.db.pedidos();
    if (mounted) setState(() => _pedidos = lista);
  }

  Future<void> _reenviar(Pedido p, {List<ItemPedido>? itens, bool? confirmarMesa, bool? aceitarPrecos}) async {
    await _st.db.reenviar(p.uuid, itens: itens, confirmarMesa: confirmarMesa, aceitarPrecos: aceitarPrecos);
    await _st.sync.atualizarContadores();
    _st.sync.agora();
  }

  Future<void> _aceitarPrecos(Pedido p) async {
    final precos = (p.detalhes?['precos'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final novos = <int, double>{};
    final niveis = <int, String>{};
    for (final x in precos) {
      final id = (x['product_id'] as num).toInt();
      novos[id] = (x['preco_atual'] as num).toDouble();
      final n = '${x['nivel'] ?? ''}'.trim().toLowerCase();
      if (n.isNotEmpty) niveis[id] = n;
    }
    final itens = p.itens.map((i) {
      final preco = novos[i.productId];
      if (preco != null) {
        return ItemPedido(
          productId: i.productId,
          descricao: i.descricao,
          unidade: i.unidade,
          quantidade: i.quantidade,
          preco: preco,
          obs: i.obs,
          pesado: i.pesado,
          nivel: niveis[i.productId] ?? i.nivel,
          composicaoRemovidos: i.composicaoRemovidos,
          composicaoAdicionais: i.composicaoAdicionais,
          composicaoLinhas: i.composicaoLinhas,
          acrescimo: i.acrescimo,
        );
      }
      return i;
    }).toList();
    for (final e in novos.entries) {
      await _st.db.atualizarPrecoProduto(e.key, e.value);
    }
    await _reenviar(p, itens: itens, aceitarPrecos: true);
  }

  Future<void> _removerIndisponiveis(Pedido p) async {
    final ids = (p.detalhes?['product_ids'] as List<dynamic>? ?? const []).map((e) => (e as num).toInt()).toSet();
    final itens = p.itens.where((i) => !ids.contains(i.productId)).toList();
    if (itens.isEmpty) {
      await _descartar(p, perguntar: false);
      return;
    }
    await _reenviar(p, itens: itens);
  }

  Future<void> _descartar(Pedido p, {bool perguntar = true}) async {
    if (perguntar &&
        !await confirmar(context, 'Descartar pedido',
            'O pedido da ${rotuloMesa(p.numero)} (${moeda(p.total)}) NÃO foi lançado no PDV e será apagado deste celular.',
            ok: 'Descartar')) {
      return;
    }
    await _st.db.descartar(p.uuid);
    await _st.sync.atualizarContadores();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos deste celular'),
        actions: [StatusConexao(sync: _st.sync), const SizedBox(width: 6)],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _st.sync,
        builder: (context, _) => _st.sync.pendentes == 0
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: _st.sync.enviando ? null : () => _st.sync.agora(),
                icon: const Icon(Icons.cloud_upload),
                label: Text(_st.sync.enviando ? 'Enviando…' : 'Enviar agora'),
              ),
      ),
      body: _pedidos.isEmpty
          ? Center(child: Text('Nenhum pedido recente.', style: TextStyle(color: cs.onSurfaceVariant)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: _pedidos.length,
              itemBuilder: (context, i) => _card(_pedidos[i], cs),
            ),
    );
  }

  Widget _card(Pedido p, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${rotuloMesa(p.numero)} · ${moeda(p.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            SeloPedido(status: p.status),
          ]),
          const SizedBox(height: 2),
          Text(
            p.status == StatusPedido.enviado
                ? 'Feito às ${hora(p.criadoEm)} · confirmado pelo PDV às ${hora(p.enviadoEm)}'
                : 'Feito às ${hora(p.criadoEm)}${p.tentativas > 0 ? ' · ${p.tentativas} tentativa(s)' : ''}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          for (final it in p.itens) ...[
            Text(
              '${quantidade(it.quantidade)} × ${it.descricao}',
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            for (final linha in it.composicaoLinhas)
              Text(linha, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            if (it.obs.isNotEmpty)
              Text('Obs: ${it.obs}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
          if ((p.erroMsg != null || p.erroCode != null) && p.status != StatusPedido.enviado) ...[
            const SizedBox(height: 6),
            SelectableText(
              [
                if (p.erroCode != null &&
                    p.erroCode!.isNotEmpty &&
                    !(p.erroMsg ?? '').contains(p.erroCode!))
                  p.erroCode!,
                if (p.erroMsg != null && p.erroMsg!.isNotEmpty) p.erroMsg!,
              ].join('\n'),
              style: TextStyle(
                fontSize: 12,
                height: 1.25,
                color: p.status == StatusPedido.erro ? cs.error : const Color(0xFFB45309),
              ),
            ),
          ],
          if (p.status == StatusPedido.erro) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: _acoes(p, cs)),
          ],
        ]),
      ),
    );
  }

  List<Widget> _acoes(Pedido p, ColorScheme cs) {
    final descartar = TextButton(
      onPressed: () => _descartar(p),
      style: TextButton.styleFrom(foregroundColor: cs.error),
      child: const Text('Descartar'),
    );

    switch (p.erroCode) {
      case 'PRECO_ALTERADO':
        final precos = (p.detalhes?['precos'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
        final nomes = {for (final i in p.itens) i.productId: i.descricao};
        return [
          for (final x in precos)
            Text(
              '${nomes[(x['product_id'] as num).toInt()] ?? 'Produto'}: '
              '${moeda((x['preco_anterior'] as num).toDouble())} → ${moeda((x['preco_atual'] as num).toDouble())}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          FilledButton(onPressed: () => _aceitarPrecos(p), child: const Text('Aceitar novos preços e enviar')),
          descartar,
        ];
      case 'MESA_FECHADA':
        return [
          FilledButton(onPressed: () => _reenviar(p, confirmarMesa: true), child: const Text('Confirmar e enviar')),
          descartar,
        ];
      case 'PRODUTO_INDISPONIVEL':
        return [
          FilledButton(onPressed: () => _removerIndisponiveis(p), child: const Text('Remover indisponíveis e enviar')),
          descartar,
        ];
      default:
        return [
          FilledButton(onPressed: () => _reenviar(p), child: const Text('Tentar de novo')),
          descartar,
        ];
    }
  }
}
