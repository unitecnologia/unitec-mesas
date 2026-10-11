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
    _st.sync.mesasVisiveis = false;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MesaTela(state: _st, numero: numero, mesa: _mesas[numero]),
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
    final (fundo, borda, texto) = switch (situacao) {
      SituacaoMesa.ocupada => (const Color(0xFF1E5A9E), const Color(0xFF1E5A9E), Colors.white),
      SituacaoMesa.aguardandoFechamento => (const Color(0xFFF59E0B), const Color(0xFFD97706), Colors.black87),
      _ => (Colors.white, const Color(0xFFCBD5E1), const Color(0xFF334155)),
    };
    final rotulo = switch (situacao) {
      SituacaoMesa.ocupada => moeda(m!.total),
      SituacaoMesa.aguardandoFechamento => 'Fechando',
      _ => 'Livre',
    };

    return Material(
      color: fundo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: m?.noCaixa == true ? const Color(0xFF7C3AED) : borda, width: m?.noCaixa == true ? 2.5 : 1),
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
              if (m?.noCaixa == true)
                Text('no caixa', style: TextStyle(fontSize: 10, color: texto.withValues(alpha: 0.85))),
            ]),
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
