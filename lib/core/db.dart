import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'formato.dart';
import 'modelos.dart';

/// Banco local (SQLite): catálogo, mesas em cache, rascunhos e a fila de pedidos.
/// Pedido gravado aqui não é apagado sem confirmação do servidor ou decisão do garçom.
class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  static Future<LocalDb> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'unitec_mesas.db'),
      version: 5,
      onCreate: (db, _) async {
        final b = db.batch();
        b.execute('''
          CREATE TABLE produtos(
            id INTEGER PRIMARY KEY, codigo TEXT, barras TEXT, descricao TEXT,
            busca TEXT, unidade TEXT, preco REAL, grupo TEXT, pesado INTEGER,
            foto_url TEXT, qtd_vendida REAL DEFAULT 0)''');
        b.execute('CREATE INDEX idx_produtos_codigo ON produtos(codigo)');
        b.execute('CREATE INDEX idx_produtos_barras ON produtos(barras)');
        b.execute('CREATE INDEX idx_produtos_grupo ON produtos(grupo)');
        b.execute('''
          CREATE TABLE grupos(
            id INTEGER PRIMARY KEY, nome TEXT NOT NULL)''');
        b.execute('''
          CREATE TABLE produto_tab_preco(
            product_id INTEGER PRIMARY KEY,
            niveis_json TEXT NOT NULL,
            precos_json TEXT NOT NULL)''');
        b.execute('''
          CREATE TABLE produto_composicao(
            product_id INTEGER NOT NULL,
            component_id INTEGER NOT NULL,
            codigo TEXT,
            descricao TEXT,
            quantidade REAL,
            preco REAL,
            is_adicional INTEGER DEFAULT 0,
            PRIMARY KEY (product_id, component_id))''');
        b.execute('CREATE INDEX idx_produto_composicao_kit ON produto_composicao(product_id)');
        b.execute('''
          CREATE TABLE mesas(
            numero INTEGER PRIMARY KEY, qtd INTEGER, total REAL, situacao INTEGER,
            no_caixa INTEGER, nome TEXT, aberta_em TEXT)''');
        b.execute('CREATE TABLE comandas(numero INTEGER PRIMARY KEY, json TEXT, atualizado_em TEXT)');
        b.execute('CREATE TABLE rascunhos(numero INTEGER PRIMARY KEY, itens TEXT, aberta_em_vista TEXT)');
        b.execute('''
          CREATE TABLE pedidos(
            uuid TEXT PRIMARY KEY, numero INTEGER NOT NULL, itens TEXT NOT NULL,
            status TEXT NOT NULL, criado_em TEXT NOT NULL, aberta_em_vista TEXT,
            erro_code TEXT, erro_msg TEXT, detalhes TEXT,
            confirmar_mesa INTEGER DEFAULT 0, aceitar_precos INTEGER DEFAULT 0,
            tentativas INTEGER DEFAULT 0, proxima_tentativa INTEGER DEFAULT 0,
            enviado_em TEXT)''');
        b.execute('CREATE INDEX idx_pedidos_status ON pedidos(status, criado_em)');
        b.execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)');
        await b.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS produto_tab_preco(
              product_id INTEGER PRIMARY KEY,
              niveis_json TEXT NOT NULL,
              precos_json TEXT NOT NULL)''');
        }
        if (oldVersion < 3) {
          await db.execute('CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT)');
          // Força novo pull do catálogo com tab_preco na próxima sync.
          await db.delete('meta', where: 'k = ?', whereArgs: ['tab_preco_sync']);
        }
        if (oldVersion < 4) {
          try {
            await db.execute('ALTER TABLE produtos ADD COLUMN foto_url TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE produtos ADD COLUMN qtd_vendida REAL DEFAULT 0');
          } catch (_) {}
          await db.execute('''
            CREATE TABLE IF NOT EXISTS grupos(
              id INTEGER PRIMARY KEY, nome TEXT NOT NULL)''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_produtos_grupo ON produtos(grupo)');
          // Força pull com foto, grupos e ranking.
          await db.delete('meta', where: 'k = ?', whereArgs: ['catalogo_v4']);
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS produto_composicao(
              product_id INTEGER NOT NULL,
              component_id INTEGER NOT NULL,
              codigo TEXT,
              descricao TEXT,
              quantidade REAL,
              preco REAL,
              is_adicional INTEGER DEFAULT 0,
              PRIMARY KEY (product_id, component_id))''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_produto_composicao_kit ON produto_composicao(product_id)');
          await db.delete('meta', where: 'k = ?', whereArgs: ['catalogo_v5']);
        }
      },
    );
    return LocalDb._(db);
  }

  // ---------------------------------------------------------------- catálogo

  /// Troca o catálogo inteiro numa transação (nunca fica pela metade).
  Future<void> substituirProdutos(
    List<dynamic> linhas, {
    Map<String, dynamic>? tabPreco,
    List<dynamic>? grupos,
    Map<String, dynamic>? composicoes,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete('produtos');
      await txn.delete('produto_tab_preco');
      await txn.delete('produto_composicao');
      await txn.delete('grupos');
      var batch = txn.batch();
      var n = 0;
      for (final l in linhas) {
        final r = l as List<dynamic>;
        final descricao = '${r[3] ?? ''}';
        batch.insert('produtos', {
          'id': (r[0] as num).toInt(),
          'codigo': '${r[1] ?? ''}',
          'barras': '${r[2] ?? ''}',
          'descricao': descricao,
          'busca': normalizarBusca('$descricao ${r[1] ?? ''}'),
          'unidade': '${r[4] ?? 'UN'}',
          'preco': (r[5] as num).toDouble(),
          'grupo': '${r[6] ?? ''}',
          'pesado': (r[7] as num).toInt(),
          'foto_url': r.length > 8 ? (r[8]?.toString() ?? '') : '',
          'qtd_vendida': r.length > 9 ? (r[9] as num?)?.toDouble() ?? 0 : 0,
        });
        if (++n % 500 == 0) {
          await batch.commit(noResult: true);
          batch = txn.batch();
        }
      }
      if (grupos != null) {
        for (final g in grupos) {
          if (g is! Map) continue;
          final id = (g['id'] as num?)?.toInt();
          final nome = '${g['nome'] ?? ''}'.trim();
          if (id == null || id <= 0 || nome.isEmpty) continue;
          batch.insert('grupos', {'id': id, 'nome': nome});
          if (++n % 500 == 0) {
            await batch.commit(noResult: true);
            batch = txn.batch();
          }
        }
      }
      if (tabPreco != null) {
        for (final e in tabPreco.entries) {
          final id = int.tryParse(e.key.toString());
          if (id == null || e.value is! Map) continue;
          final info = TabPrecoInfo.fromApi(Map<String, dynamic>.from(e.value as Map));
          if (!info.ativo) continue;
          batch.insert('produto_tab_preco', info.toRow(id));
          if (++n % 500 == 0) {
            await batch.commit(noResult: true);
            batch = txn.batch();
          }
        }
      }
      if (composicoes != null) {
        for (final e in composicoes.entries) {
          final kitId = int.tryParse(e.key.toString());
          if (kitId == null || e.value is! List) continue;
          for (final raw in e.value as List) {
            if (raw is! Map) continue;
            final c = CompComponente.fromApi(Map<String, dynamic>.from(raw));
            if (c.id <= 0) continue;
            batch.insert('produto_composicao', {
              'product_id': kitId,
              'component_id': c.id,
              'codigo': c.codigo,
              'descricao': c.descricao,
              'quantidade': c.quantidade,
              'preco': c.preco,
              'is_adicional': c.isAdicional ? 1 : 0,
            });
            if (++n % 500 == 0) {
              await batch.commit(noResult: true);
              batch = txn.batch();
            }
          }
        }
      }
      await batch.commit(noResult: true);
      // Só marca sync OK quando a API enviou a chave tab_preco (mesmo vazia).
      if (tabPreco != null) {
        await txn.insert(
          'meta',
          {'k': 'tab_preco_sync', 'v': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.insert(
        'meta',
        {'k': 'catalogo_v4', 'v': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (composicoes != null) {
        await txn.insert(
          'meta',
          {'k': 'catalogo_v5', 'v': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<CompComponente>> composicaoDoProduto(int productId) async {
    final rows = await _db.query(
      'produto_composicao',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'is_adicional DESC, descricao ASC',
    );
    return rows.map(CompComponente.fromRow).toList();
  }

  Future<TabPrecoInfo?> tabPrecoDoProduto(int productId) async {
    final rows = await _db.query('produto_tab_preco', where: 'product_id = ?', whereArgs: [productId], limit: 1);
    if (rows.isEmpty) return null;
    final info = TabPrecoInfo.fromRow(rows.first);
    return info.ativo ? info : null;
  }

  Future<int> contarProdutos() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM produtos')) ?? 0;

  Future<String?> meta(String key) async {
    final rows = await _db.query('meta', where: 'k = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  Future<void> setMeta(String key, String value) =>
      _db.insert('meta', {'k': key, 'v': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<GrupoCatalogo>> listarGrupos() async {
    final rows = await _db.query('grupos', orderBy: 'nome');
    return rows.map(GrupoCatalogo.fromRow).toList();
  }

  /// Busca catálogo. Sem termo: ordena pelos mais vendidos (60 dias, vindo do servidor).
  /// Com [grupo], filtra pelo nome do cadastro de Grupos (Mostrar no App).
  Future<List<Produto>> buscarProdutos(String termo, {String? grupo, int limite = 80}) async {
    final t = normalizarBusca(termo);
    final g = (grupo ?? '').trim();
    final grupoClause = g.isEmpty ? '' : ' AND UPPER(grupo) = UPPER(?)';

    if (t.isEmpty) {
      final rows = await _db.rawQuery(
        'SELECT * FROM produtos WHERE 1=1$grupoClause '
        'ORDER BY qtd_vendida DESC, descricao LIMIT ?',
        [...(g.isEmpty ? <Object?>[] : [g]), limite],
      );
      return rows.map(Produto.fromRow).toList();
    }

    final palavras = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(4).toList();
    final where = <String>[];
    final args = <Object?>[];
    for (final w in palavras) {
      where.add('busca LIKE ?');
      args.add('%$w%');
    }
    if (g.isNotEmpty) args.add(g);

    final rows = await _db.rawQuery(
      'SELECT * FROM produtos WHERE ((codigo = ? OR barras = ?) OR (${where.join(' AND ')}))$grupoClause '
      'ORDER BY (codigo = ? OR barras = ?) DESC, qtd_vendida DESC, (busca LIKE ?) DESC, descricao LIMIT ?',
      [t, t, ...args, t, t, '$t%', limite],
    );
    return rows.map(Produto.fromRow).toList();
  }

  Future<Map<int, Produto>> produtosPorId(Iterable<int> ids) async {
    final lista = ids.toSet().toList();
    if (lista.isEmpty) return {};
    final rows = await _db.query('produtos',
        where: 'id IN (${List.filled(lista.length, '?').join(',')})', whereArgs: lista);
    return {for (final r in rows) r['id'] as int: Produto.fromRow(r)};
  }

  Future<void> atualizarPrecoProduto(int id, double preco) =>
      _db.update('produtos', {'preco': preco}, where: 'id = ?', whereArgs: [id]);

  // ---------------------------------------------------------------- mesas

  Future<void> substituirMesas(List<MesaInfo> mesas) async {
    await _db.transaction((txn) async {
      await txn.delete('mesas');
      final b = txn.batch();
      for (final m in mesas) {
        b.insert('mesas', m.toRow());
      }
      await b.commit(noResult: true);
    });
  }

  Future<void> salvarMesa(MesaInfo mesa) async {
    if (mesa.qtd <= 0 && !mesa.noCaixa) {
      await _db.delete('mesas', where: 'numero = ?', whereArgs: [mesa.numero]);
      return;
    }
    await _db.insert('mesas', mesa.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<int, MesaInfo>> mesas() async {
    final rows = await _db.query('mesas');
    return {for (final r in rows) r['numero'] as int: MesaInfo.fromRow(r)};
  }

  Future<void> salvarComanda(int numero, Map<String, dynamic> json) => _db.insert(
        'comandas',
        {'numero': numero, 'json': jsonEncode(json), 'atualizado_em': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<(Map<String, dynamic>, DateTime?)?> comanda(int numero) async {
    final rows = await _db.query('comandas', where: 'numero = ?', whereArgs: [numero]);
    if (rows.isEmpty) return null;
    try {
      return (
        jsonDecode(rows.first['json'] as String) as Map<String, dynamic>,
        DateTime.tryParse('${rows.first['atualizado_em']}'),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- rascunhos

  Future<void> salvarRascunho(int numero, List<ItemPedido> itens, String? abertaEmVista) async {
    if (itens.isEmpty) {
      await _db.delete('rascunhos', where: 'numero = ?', whereArgs: [numero]);
      return;
    }
    await _db.insert(
      'rascunhos',
      {'numero': numero, 'itens': ItemPedido.listToJson(itens), 'aberta_em_vista': abertaEmVista},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<(List<ItemPedido>, String?)?> rascunho(int numero) async {
    final rows = await _db.query('rascunhos', where: 'numero = ?', whereArgs: [numero]);
    if (rows.isEmpty) return null;
    return (ItemPedido.listFromJson(rows.first['itens'] as String?), rows.first['aberta_em_vista'] as String?);
  }

  // ---------------------------------------------------------------- pedidos

  /// Grava o pedido e apaga o rascunho da mesa na mesma transação.
  Future<void> criarPedido(Pedido pedido) async {
    await _db.transaction((txn) async {
      await txn.insert('pedidos', {
        'uuid': pedido.uuid,
        'numero': pedido.numero,
        'itens': ItemPedido.listToJson(pedido.itens),
        'status': StatusPedido.pendente,
        'criado_em': pedido.criadoEm.toIso8601String(),
        'aberta_em_vista': pedido.abertaEmVista,
      });
      await txn.delete('rascunhos', where: 'numero = ?', whereArgs: [pedido.numero]);
    });
  }

  Future<List<Pedido>> pedidosParaEnviar(int agoraMs) async {
    final rows = await _db.query('pedidos',
        where: 'status = ? AND proxima_tentativa <= ?',
        whereArgs: [StatusPedido.pendente, agoraMs],
        orderBy: 'criado_em');
    return rows.map(Pedido.fromRow).toList();
  }

  Future<List<Pedido>> pedidos({int? numero, bool incluirEnviadosRecentes = true}) async {
    final desde = DateTime.now().subtract(const Duration(hours: 12)).toIso8601String();
    final where = StringBuffer('(status != ?');
    final args = <Object?>[StatusPedido.enviado];
    if (incluirEnviadosRecentes) {
      where.write(' OR enviado_em >= ?');
      args.add(desde);
    }
    where.write(')');
    if (numero != null) {
      where.write(' AND numero = ?');
      args.add(numero);
    }
    final rows = await _db.query('pedidos', where: where.toString(), whereArgs: args, orderBy: 'criado_em DESC');
    return rows.map(Pedido.fromRow).toList();
  }

  Future<Pedido?> pedido(String uuid) async {
    final rows = await _db.query('pedidos', where: 'uuid = ?', whereArgs: [uuid]);
    return rows.isEmpty ? null : Pedido.fromRow(rows.first);
  }

  Future<(int pendentes, int erros)> contarPedidos() async {
    final rows = await _db.rawQuery(
      'SELECT status, COUNT(*) c FROM pedidos WHERE status IN (?, ?) GROUP BY status',
      [StatusPedido.pendente, StatusPedido.erro],
    );
    var pendentes = 0;
    var erros = 0;
    for (final r in rows) {
      if (r['status'] == StatusPedido.pendente) pendentes = r['c'] as int;
      if (r['status'] == StatusPedido.erro) erros = r['c'] as int;
    }
    return (pendentes, erros);
  }

  Future<Set<int>> mesasComPendencia() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT numero FROM pedidos WHERE status IN (?, ?)',
      [StatusPedido.pendente, StatusPedido.erro],
    );
    return rows.map((r) => r['numero'] as int).toSet();
  }

  Future<void> marcarEnviado(String uuid) => _db.update(
        'pedidos',
        {
          'status': StatusPedido.enviado,
          'enviado_em': DateTime.now().toIso8601String(),
          'erro_code': null,
          'erro_msg': null,
          'detalhes': null,
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );

  /// Falha temporária: continua pendente e tenta de novo depois.
  Future<void> reagendar(String uuid, String mensagem, int proximaMs, {String? code}) => _db.rawUpdate(
        'UPDATE pedidos SET erro_msg = ?, erro_code = ?, proxima_tentativa = ?, tentativas = tentativas + 1 '
        'WHERE uuid = ? AND status = ?',
        [mensagem, code, proximaMs, uuid, StatusPedido.pendente],
      );

  /// Conflito: aguarda decisão do garçom.
  Future<void> marcarErro(String uuid, String code, String mensagem, Map<String, dynamic>? detalhes) => _db.update(
        'pedidos',
        {
          'status': StatusPedido.erro,
          'erro_code': code,
          'erro_msg': mensagem,
          'detalhes': detalhes == null ? null : jsonEncode(detalhes),
        },
        where: 'uuid = ? AND status = ?',
        whereArgs: [uuid, StatusPedido.pendente],
      );

  /// Garçom resolveu o conflito: volta para a fila com os ajustes.
  Future<void> reenviar(
    String uuid, {
    List<ItemPedido>? itens,
    bool? confirmarMesa,
    bool? aceitarPrecos,
  }) =>
      _db.update(
        'pedidos',
        {
          'status': StatusPedido.pendente,
          'proxima_tentativa': 0,
          'erro_code': null,
          'erro_msg': null,
          'detalhes': null,
          if (itens != null) 'itens': ItemPedido.listToJson(itens),
          if (confirmarMesa != null) 'confirmar_mesa': confirmarMesa ? 1 : 0,
          if (aceitarPrecos != null) 'aceitar_precos': aceitarPrecos ? 1 : 0,
        },
        where: 'uuid = ? AND status != ?',
        whereArgs: [uuid, StatusPedido.enviado],
      );

  /// Só pedidos que não foram enviados, por decisão explícita do garçom.
  Future<void> descartar(String uuid) =>
      _db.delete('pedidos', where: 'uuid = ? AND status != ?', whereArgs: [uuid, StatusPedido.enviado]);

  Future<void> limparHistorico() async {
    final limite = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
    await _db.delete('pedidos', where: 'status = ? AND enviado_em < ?', whereArgs: [StatusPedido.enviado, limite]);
  }
}
