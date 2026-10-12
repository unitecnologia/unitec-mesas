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
  });

  final int id;
  final String codigo;
  final String barras;
  final String descricao;
  final String unidade;
  final double preco;
  final String grupo;
  final bool pesado;

  factory Produto.fromRow(Map<String, Object?> r) => Produto(
        id: r['id'] as int,
        codigo: '${r['codigo'] ?? ''}',
        barras: '${r['barras'] ?? ''}',
        descricao: '${r['descricao'] ?? ''}',
        unidade: '${r['unidade'] ?? 'UN'}',
        preco: (r['preco'] as num?)?.toDouble() ?? 0,
        grupo: '${r['grupo'] ?? ''}',
        pesado: (r['pesado'] as int? ?? 0) == 1,
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
  });

  final int productId;
  final String descricao;
  final String unidade;
  double quantidade;
  double preco;
  String obs;
  final bool pesado;

  /// Nível Tab. Preço (varejo/atacado/especial). Null = produto sem a flag.
  final String? nivel;

  double get total => double.parse((quantidade * preco).toStringAsFixed(2));

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'descricao': descricao,
        'unidade': unidade,
        'quantidade': quantidade,
        'preco': preco,
        'obs': obs,
        'pesado': pesado,
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
    );
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
                })
            .toList(),
        'aberta_em_vista': abertaEmVista,
        'confirmar_mesa': confirmarMesa,
        'aceitar_precos': aceitarPrecos,
      };
}
