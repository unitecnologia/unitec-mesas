import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/formato.dart';
import '../core/modelos.dart';
import 'configuracoes_tela.dart';
import 'mesa_tela.dart';
import 'pedidos_tela.dart';
import 'widgets.dart';

class MesasTela extends StatefulWidget {
  const MesasTela({super.key, required this.state});

  final AppState state;

  @override
  State<MesasTela> createState() => _MesasTelaState();
}

class _MesasTelaState extends State<MesasTela> {
  Map<int, MesaInfo> _mesas = {};
  Set<int> _comPendencia = {};
  int _produtos = 0;

  AppState get _st => widget.state;

  @override
  void initState() {
    super.initState();
    _st.sync.mesasVisiveis = true;
    _st.sync.versaoDados.addListener(_recarregar);
    _recarregar();
  }

  @override
  void dispose() {
    _st.sync.versaoDados.removeListener(_recarregar);
    _st.sync.mesasVisiveis = false;
    super.dispose();
  }

  Future<void> _recarregar() async {
    final mesas = await _st.db.mesas();
    final pend = await _st.db.mesasComPendencia();
    final produtos = await _st.db.contarProdutos();
    if (!mounted) return;
    setState(() {
      _mesas = mesas;
      _comPendencia = pend;
      _produtos = produtos;
    });
  }

  Future<void> _abrirMesa(int numero) async {
    final mesa = _mesas[numero];
    if (mesa != null && mesa.bloqueadaParaLancamento) {
      final ver = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${rotuloMesa(numero)} travada'),
          content: Text(
            mesa.situacao == SituacaoMesa.aguardandoFechamento
                ? 'Mesa em fechamento no caixa. Não é possível lançar itens até o caixa liberar.'
                : 'Mesa em atendimento no caixa${mesa.nomeNoCaixa.isNotEmpty ? ' (${mesa.nomeNoCaixa})' : ''}. '
                    'Não é possível lançar itens até o caixa liberar.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ver comanda')),
          ],
        ),
      );
      if (ver != true || !mounted) return;
    }

    _st.sync.mesasVisiveis = false;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MesaTela(state: _st, numero: numero, mesa: mesa),
    ));
    if (!mounted) return;
    _st.sync.mesasVisiveis = true;
    _st.sync.agora(forcarMesas: true);
    _recarregar();
  }

  Future<void> _abrirPedidos() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PedidosTela(state: _st)));
    if (mounted) _recarregar();
  }

  Future<void> _abrirConfiguracoes() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConfiguracoesTela(state: _st),
    ));
  }

  Future<void> _menu(String acao) async {
    switch (acao) {
      case 'produtos':
        avisar(context, 'Atualizando produtos…');
        final ok = await _st.sync.atualizarCatalogo(forcar: true);
        if (mounted) {
          avisar(context, ok ? 'Produtos atualizados.' : (_st.sync.avisoCatalogo ?? 'Falha ao atualizar.'), erro: !ok);
        }
      case 'configuracoes':
        await _abrirConfiguracoes();
      case 'sair':
        final pend = _st.sync.pendentes + _st.sync.erros;
        final texto = pend > 0
            ? 'Há $pend pedido(s) não enviado(s). Eles ficam guardados neste celular e serão enviados no próximo login.'
            : 'Encerrar a sessão deste garçom?';
        if (await confirmar(context, 'Trocar garçom', texto, ok: 'Sair')) {
          await _st.sair();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _st.config;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Mesas', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('${cfg.userName} · ${cfg.empresaNome}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          StatusConexao(sync: _st.sync, onTap: _abrirPedidos),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'produtos', child: Text('Atualizar produtos')),
              PopupMenuItem(value: 'configuracoes', child: Text('Configurações')),
              PopupMenuItem(value: 'sair', child: Text('Trocar garçom')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_produtos == 0)
          MaterialBanner(
            content: const Text('Catálogo de produtos ainda não baixado. Conecte ao servidor para lançar itens.'),
            actions: [TextButton(onPressed: () => _menu('produtos'), child: const Text('Baixar'))],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _st.sync.agora(forcarMesas: true);
              await Future<void>.delayed(const Duration(milliseconds: 600));
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.05,
              ),
              itemCount: cfg.qtdMesas,
              itemBuilder: (context, i) {
                final numero = i + 1;
                return _MesaTile(
                  numero: numero,
                  mesa: _mesas[numero],
                  pendente: _comPendencia.contains(numero),
                  onTap: () => _abrirMesa(numero),
                );
              },
            ),
          ),
        ),
        ListenableBuilder(
          listenable: _st.sync,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Text(
              _st.sync.online == false
                  ? 'Offline — situação das mesas de ${hora(_st.sync.mesasAtualizadasEm)}. Pedidos ficam guardados e saem sozinhos.'
                  : 'Atualizado às ${hora(_st.sync.mesasAtualizadasEm)}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ]),
    );
  }
}

class _MesaTile extends StatelessWidget {
  const _MesaTile({required this.numero, required this.mesa, required this.pendente, required this.onTap});

  final int numero;
  final MesaInfo? mesa;
  final bool pendente;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = mesa;
    final situacao = m?.situacao ?? SituacaoMesa.livre;
    // Mesmas cores do painel Mesas do PDV (erp-pdv-mesas.css):
    // Livre=verde | Ocupada=amarelo | Aguardando=vermelho | No caixa/outro=cinza.
    final noCaixa = m?.noCaixa == true;
    final aguardando = situacao == SituacaoMesa.aguardandoFechamento;
    final (fundo, borda, texto) = noCaixa && !aguardando
        ? (const Color(0xFF64748B), const Color(0xFF475569), Colors.white)
        : switch (situacao) {
            SituacaoMesa.ocupada => (const Color(0xFFEAB308), const Color(0xFFCA8A04), const Color(0xFF422006)),
            SituacaoMesa.aguardandoFechamento => (const Color(0xFFDC2626), const Color(0xFFB91C1C), Colors.white),
            _ => (const Color(0xFF16A34A), const Color(0xFF15803D), Colors.white),
          };
    final rotulo = switch (situacao) {
      SituacaoMesa.ocupada => moeda(m!.total),
      SituacaoMesa.aguardandoFechamento => m != null && m.total > 0 ? moeda(m.total) : 'Aguardando',
      _ => 'Livre',
    };

    return Material(
      color: fundo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borda, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(numero.toString().padLeft(2, '0'),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: texto)),
              Text(rotulo,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: texto),
                  overflow: TextOverflow.ellipsis),
              if (noCaixa)
                Text('no caixa', style: TextStyle(fontSize: 10, color: texto.withValues(alpha: 0.85))),
              if (aguardando && !noCaixa)
                Text('aguardando', style: TextStyle(fontSize: 10, color: texto.withValues(alpha: 0.9))),
            ]),
          ),
          if (m?.bloqueadaParaLancamento == true)
            Positioned(
              top: 6,
              left: 6,
              child: Icon(Icons.lock, size: 14, color: texto.withValues(alpha: 0.9)),
            ),
          if (pendente)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.cloud_upload, size: 14, color: Color(0xFFEA580C)),
            ),
        ]),
      ),
    );
  }
}
