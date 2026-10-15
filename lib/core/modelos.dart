import 'dart:convert';

class Produto {
  Produto({
    required this.id,
    required this.codigo,
    required this.barras,
    required this.descricao,
    required this.unidade,
    required this.preco,
    required this.grupo,
    required this.pesado,
    this.fotoUrl = '',
    this.qtdVendida = 0,
  });

  final int id;
  final String codigo;
  final String barras;
  final String descricao;
  final String unidade;
  final double preco;
  final String grupo;
  final bool pesado;

  /// Caminho relativo da foto no ERP (ex.: /api/v1/mesas/produtos/1/foto?v=…).
  final String fotoUrl;

  /// Quantidade vendida nos últimos 60 dias (ranking do servidor).
  final double qtdVendida;

  factory Produto.fromRow(Map<String, Object?> r) => Produto(
        id: r['id'] as int,
        codigo: '${r['codigo'] ?? ''}',
        barras: '${r['barras'] ?? ''}',
        descricao: '${r['descricao'] ?? ''}',
        unidade: '${r['unidade'] ?? 'UN'}',
        preco: (r['preco'] as num?)?.toDouble() ?? 0,
        grupo: '${r['grupo'] ?? ''}',
        pesado: (r['pesado'] as int? ?? 0) == 1,
        fotoUrl: '${r['foto_url'] ?? ''}',
        qtdVendida: (r['qtd_vendida'] as num?)?.toDouble() ?? 0,
      );
}

/// Grupo do cadastro ERP (ativo + Mostrar no App), igual ao Força de Vendas.
class GrupoCatalogo {
  GrupoCatalogo({required this.id, required this.nome});

  final int id;
  final String nome;

  factory GrupoCatalogo.fromApi(Map<String, dynamic> m) => GrupoCatalogo(
        id: (m['id'] as num?)?.toInt() ?? 0,
        nome: '${m['nome'] ?? ''}'.trim(),
      );

  factory GrupoCatalogo.fromRow(Map<String, Object?> r) => GrupoCatalogo(
        id: r['id'] as int,
        nome: '${r['nome'] ?? ''}',
      );
}

/// Tab. Preço do produto (só existe com usa_tab_preco no ERP).
class TabPrecoInfo {
  TabPrecoInfo({required this.niveis, required this.precos});

  final List<String> niveis;
  final Map<String, double> precos;

  bool get ativo => niveis.isNotEmpty;

  double precoDo(String nivel) => precos[nivel] ?? 0;

  factory TabPrecoInfo.fromApi(Map<String, dynamic> m) {
    final niveisRaw = m['niveis'];
    final precosRaw = m['precos'];
    final niveis = <String>[];
    if (niveisRaw is List) {
      for (final n in niveisRaw) {
        final s = '$n'.trim().toLowerCase();
        if (s == 'varejo' || s == 'atacado' || s == 'especial') niveis.add(s);
      }
    }
    final precos = <String, double>{};
    if (precosRaw is Map) {
      for (final e in precosRaw.entries) {
        final k = '${e.key}'.trim().toLowerCase();
        if (niveis.contains(k)) {
          precos[k] = (e.value as num?)?.toDouble() ?? 0;
        }
      }
    }
    // Ordem estável V → A → E
    const ordem = ['varejo', 'atacado', 'especial'];
    final ordered = [for (final n in ordem) if (niveis.contains(n)) n];
    return TabPrecoInfo(niveis: ordered, precos: precos);
  }

  factory TabPrecoInfo.fromRow(Map<String, Object?> r) {
    List<String> niveis = const [];
    Map<String, double> precos = const {};
    try {
      final n = jsonDecode('${r['niveis_json'] ?? '[]'}');
      if (n is List) {
        niveis = n.map((e) => '$e'.toLowerCase()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    try {
      final p = jsonDecode('${r['precos_json'] ?? '{}'}');
      if (p is Map) {
        precos = {
          for (final e in p.entries) '${e.key}'.toLowerCase(): (e.value as num?)?.toDouble() ?? 0,
        };
      }
    } catch (_) {}
    return TabPrecoInfo(niveis: niveis, precos: precos);
  }

  Map<String, Object?> toRow(int productId) => {
        'product_id': productId,
        'niveis_json': jsonEncode(niveis),
        'precos_json': jsonEncode(precos),
      };
}

/// Situação vinda do servidor (mesmas regras do painel de mesas do PDV).
class SituacaoMesa {
  static const livre = 0;
  static const ocupada = 1;
  static const aguardandoFechamento = 2;
}

class MesaInfo {
  MesaInfo({
    required this.numero,
    this.qtd = 0,
    this.total = 0,
    this.situacao = SituacaoMesa.livre,
    this.noCaixa = false,
    this.nomeNoCaixa = '',
    this.abertaEm,
  });

  final int numero;
  final int qtd;
  final double total;
  final int situacao;
  final bool noCaixa;
  final String nomeNoCaixa;
  final String? abertaEm;

  /// Pré-conta / caixa: garçom não lança itens até o caixa liberar (mesma regra do PDV).
  bool get bloqueadaParaLancamento =>
      situacao == SituacaoMesa.aguardandoFechamento || noCaixa;

  factory MesaInfo.fromRow(Map<String, Object?> r) => MesaInfo(
        numero: r['numero'] as int,
        qtd: r['qtd'] as int? ?? 0,
        total: (r['total'] as num?)?.toDouble() ?? 0,
        situacao: r['situacao'] as int? ?? 0,
        noCaixa: (r['no_caixa'] as int? ?? 0) == 1,
        nomeNoCaixa: '${r['nome'] ?? ''}',
        abertaEm: r['aberta_em'] as String?,
      );

  /// Linha compacta da API: [numero, qtd, total, situacao, no_caixa, nome, aberta_em]
  factory MesaInfo.fromApi(List<dynamic> l) => MesaInfo(
        numero: (l[0] as num).toInt(),
        qtd: (l[1] as num).toInt(),
        total: (l[2] as num).toDouble(),
        situacao: (l[3] as num).toInt(),
        noCaixa: (l[4] as num).toInt() == 1,
        nomeNoCaixa: '${l[5] ?? ''}',
        abertaEm: l[6] as String?,
      );

  factory MesaInfo.fromResumo(Map<String, dynamic> m) => MesaInfo(
        numero: (m['numero'] as num).toInt(),
        qtd: (m['qtd_itens'] as num? ?? 0).toInt(),
        total: (m['total'] as num? ?? 0).toDouble(),
        situacao: (m['situacao'] as num? ?? 0).toInt(),
        noCaixa: m['no_caixa'] == true,
        nomeNoCaixa: '${m['nome_no_caixa'] ?? ''}',
        abertaEm: m['aberta_em'] as String?,
      );

  Map<String, Object?> toRow() => {
        'numero': numero,
        'qtd': qtd,
        'total': total,
        'situacao': situacao,
        'no_caixa': noCaixa ? 1 : 0,
        'nome': nomeNoCaixa,
        'aberta_em': abertaEm,
      };
}

/// Componente de composição vindo do catálogo ERP.
class CompComponente {
  CompComponente({
    required this.id,
    required this.codigo,
    required this.descricao,
    required this.quantidade,
    required this.preco,
    required this.isAdicional,
  });

  final int id;
  final String codigo;
  final String descricao;
  final double quantidade;
  final double preco;
  final bool isAdicional;

  /// Valor unitário do adicional no kit (preço × qtd da composição).
  double get valorUnitario => double.parse((preco * quantidade).toStringAsFixed(2));

  factory CompComponente.fromApi(Map<String, dynamic> m) => CompComponente(
        id: (m['id'] as num?)?.toInt() ?? 0,
        codigo: '${m['codigo'] ?? ''}',
        descricao: '${m['descricao'] ?? ''}'.trim(),
        quantidade: (m['quantidade'] as num?)?.toDouble() ?? 1,
        preco: (m['preco'] as num?)?.toDouble() ?? 0,
        isAdicional: m['is_adicional'] == true || m['is_adicional'] == 1,
      );

  factory CompComponente.fromRow(Map<String, Object?> r) => CompComponente(
        id: r['component_id'] as int,
        codigo: '${r['codigo'] ?? ''}',
        descricao: '${r['descricao'] ?? ''}',
        quantidade: (r['quantidade'] as num?)?.toDouble() ?? 1,
        preco: (r['preco'] as num?)?.toDouble() ?? 0,
        isAdicional: (r['is_adicional'] as int? ?? 0) == 1,
      );
}

class ItemPedido {
  ItemPedido({
    required this.productId,
    required this.descricao,
    required this.unidade,
    required this.quantidade,
    required this.preco,
    this.obs = '',
    this.pesado = false,
    this.nivel,
    List<int>? composicaoRemovidos,
    List<int>? composicaoAdicionais,
    List<String>? composicaoLinhas,
    this.acrescimo = 0,
  })  : composicaoRemovidos = List<int>.from(composicaoRemovidos ?? const []),
        composicaoAdicionais = List<int>.from(composicaoAdicionais ?? const []),
        composicaoLinhas = List<String>.from(composicaoLinhas ?? const []);

  final int productId;
  final String descricao;
  final String unidade;
  double quantidade;
  double preco;
  String obs;
  final bool pesado;

  /// Nível Tab. Preço (varejo/atacado/especial). Null = produto sem a flag.
  final String? nivel;

  /// Componentes base desmarcados (SEM …).
  List<int> composicaoRemovidos;

  /// Adicionais marcados (extras cobrados).
  List<int> composicaoAdicionais;

  /// Textos para exibição/cozinha (fora de obs): SEM … / ADICIONAL: …
  List<String> composicaoLinhas;

  /// Valor total dos adicionais para a quantidade do item.
  double acrescimo;

  double get total => double.parse(((quantidade * preco) + acrescimo).toStringAsFixed(2));

  String get _chaveComp {
    final r = [...composicaoRemovidos]..sort();
    final a = [...composicaoAdicionais]..sort();
    return '${r.join(',')}|${a.join(',')}';
  }

  bool mesmaSelecaoComposicao(ItemPedido o) => _chaveComp == o._chaveComp;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'descricao': descricao,
        'unidade': unidade,
        'quantidade': quantidade,
        'preco': preco,
        'obs': obs,
        'pesado': pesado,
        'acrescimo': acrescimo,
        'composicao_removidos': composicaoRemovidos,
        'composicao_adicionais': composicaoAdicionais,
        if (composicaoLinhas.isNotEmpty) 'composicao_linhas': composicaoLinhas,
        if (nivel != null && nivel!.isNotEmpty) 'nivel': nivel,
        if (nivel != null && nivel!.isNotEmpty) 'tabela_nivel': nivel,
      };

  factory ItemPedido.fromJson(Map<String, dynamic> j) {
    final nivel = '${j['nivel'] ?? j['tabela_nivel'] ?? ''}'.trim().toLowerCase();
    return ItemPedido(
      productId: (j['product_id'] as num).toInt(),
      descricao: '${j['descricao'] ?? ''}',
      unidade: '${j['unidade'] ?? 'UN'}',
      quantidade: (j['quantidade'] as num).toDouble(),
      preco: (j['preco'] as num).toDouble(),
      obs: '${j['obs'] ?? ''}',
      pesado: j['pesado'] == true,
      nivel: nivel.isNotEmpty ? nivel : null,
      acrescimo: (j['acrescimo'] as num?)?.toDouble() ?? 0,
      composicaoRemovidos: _idsJson(j['composicao_removidos']),
      composicaoAdicionais: _idsJson(j['composicao_adicionais']),
      composicaoLinhas: _linhasJson(j['composicao_linhas']),
    );
  }

  static List<String> _linhasJson(dynamic raw) {
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if (e is String && e.trim().isNotEmpty)
          e.trim()
        else if (e is Map && '${e['texto'] ?? ''}'.trim().isNotEmpty)
          '${e['texto']}'.trim(),
    ];
  }

  static List<int> _idsJson(dynamic raw) {
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if ((e is num ? e.toInt() : int.tryParse('$e') ?? 0) > 0) (e is num ? e.toInt() : int.parse('$e')),
    ];
  }

  static List<ItemPedido> listFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final l = jsonDecode(raw) as List<dynamic>;
      return l.map((e) => ItemPedido.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<ItemPedido> itens) => jsonEncode(itens.map((e) => e.toJson()).toList());
}

/// Situação do pedido no celular. "enviado" só com confirmação do servidor.
class StatusPedido {
  static const pendente = 'pendente';
  static const enviado = 'enviado';
  static const erro = 'erro';
}

class Pedido {
  Pedido({
    required this.uuid,
    required this.numero,
    required this.itens,
    required this.status,
    required this.criadoEm,
    this.abertaEmVista,
    this.erroCode,
    this.erroMsg,
    this.detalhes,
    this.confirmarMesa = false,
    this.aceitarPrecos = false,
    this.tentativas = 0,
    this.proximaTentativa = 0,
    this.enviadoEm,
  });

  final String uuid;
  final int numero;
  final List<ItemPedido> itens;
  final String status;
  final DateTime criadoEm;
  final String? abertaEmVista;
  final String? erroCode;
  final String? erroMsg;
  final Map<String, dynamic>? detalhes;
  final bool confirmarMesa;
  final bool aceitarPrecos;
  final int tentativas;
  final int proximaTentativa;
  final DateTime? enviadoEm;

  double get total => itens.fold(0.0, (s, i) => s + i.total);

  factory Pedido.fromRow(Map<String, Object?> r) {
    Map<String, dynamic>? detalhes;
    final raw = r['detalhes'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        detalhes = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    return Pedido(
      uuid: r['uuid'] as String,
      numero: r['numero'] as int,
      itens: ItemPedido.listFromJson(r['itens'] as String?),
      status: r['status'] as String,
      criadoEm: DateTime.tryParse('${r['criado_em']}') ?? DateTime.now(),
      abertaEmVista: r['aberta_em_vista'] as String?,
      erroCode: r['erro_code'] as String?,
      erroMsg: r['erro_msg'] as String?,
      detalhes: detalhes,
      confirmarMesa: (r['confirmar_mesa'] as int? ?? 0) == 1,
      aceitarPrecos: (r['aceitar_precos'] as int? ?? 0) == 1,
      tentativas: r['tentativas'] as int? ?? 0,
      proximaTentativa: r['proxima_tentativa'] as int? ?? 0,
      enviadoEm: DateTime.tryParse('${r['enviado_em'] ?? ''}'),
    );
  }

  Map<String, dynamic> corpoEnvio() => {
        'uuid': uuid,
        'numero': numero,
        'itens': itens
            .map((i) => {
                  'product_id': i.productId,
                  'quantidade': i.quantidade,
                  'preco': i.preco,
                  if (i.obs.trim().isNotEmpty) 'obs': i.obs.trim(),
                  if (i.nivel != null && i.nivel!.isNotEmpty) 'nivel': i.nivel,
                  if (i.nivel != null && i.nivel!.isNotEmpty) 'tabela_nivel': i.nivel,
                  if (i.composicaoRemovidos.isNotEmpty) 'composicao_removidos': i.composicaoRemovidos,
                  if (i.composicaoAdicionais.isNotEmpty) 'composicao_adicionais': i.composicaoAdicionais,
                })
            .toList(),
        'aberta_em_vista': abertaEmVista,
        'confirmar_mesa': confirmarMesa,
        'aceitar_precos': aceitarPrecos,
      };
}
