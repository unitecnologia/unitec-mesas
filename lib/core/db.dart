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
      version: 1,
      onCreate: (db, _) async {
        final b = db.batch();
        b.execute('''
          CREATE TABLE produtos(
            id INTEGER PRIMARY KEY, codigo TEXT, barras TEXT, descricao TEXT,
            busca TEXT, unidade TEXT, preco REAL, grupo TEXT, pesado INTEGER)''');
        b.execute('CREATE INDEX idx_produtos_codigo ON produtos(codigo)');
        b.execute('CREATE INDEX idx_produtos_barras ON produtos(barras)');
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
        await b.commit(noResult: true);
      },
    );
    return LocalDb._(db);
  }

  // ---------------------------------------------------------------- catálogo

  /// Troca o catálogo inteiro numa transação (nunca fica pela metade).
  Future<void> substituirProdutos(List<dynamic> linhas) async {
    await _db.transaction((txn) async {
      await txn.delete('produtos');
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
        });
        if (++n % 500 == 0) {
          await batch.commit(noResult: true);
          batch = txn.batch();
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int> contarProdutos() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM produtos')) ?? 0;

  Future<List<Produto>> buscarProdutos(String termo, {int limite = 60}) async {
    final t = normalizarBusca(termo);
    if (t.isEmpty) {
      final rows = await _db.query('produtos', orderBy: 'descricao', limit: limite);
      return rows.map(Produto.fromRow).toList();
    }

    final palavras = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(4).toList();
    final where = <String>[];
    final args = <Object?>[];
    for (final w in palavras) {
      where.add('busca LIKE ?');
      args.add('%$w%');
    }

    final rows = await _db.rawQuery(
      'SELECT * FROM produtos WHERE (codigo = ? OR barras = ?) OR (${where.join(' AND ')}) '
      'ORDER BY (codigo = ? OR barras = ?) DESC, (busca LIKE ?) DESC, descricao LIMIT ?',
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
