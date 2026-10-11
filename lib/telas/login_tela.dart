import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import 'widgets.dart';

/// Login do garçom: usuário com "Mesas" liberado em Permissões e a senha do app.
class LoginTela extends StatefulWidget {
  const LoginTela({super.key, required this.state});

  final AppState state;

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _senha = TextEditingController();
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _usuarios = [];
  int? _empresaId;
  int? _userId;
  bool _carregando = true;
  bool _entrando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final info = await widget.state.api.info();
      final empresas = (info['empresas'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final anterior = widget.state.config.empresaId;
      final id = empresas.any((e) => e['id'] == anterior)
          ? anterior
          : (empresas.isNotEmpty ? (empresas.first['id'] as num).toInt() : null);
      setState(() {
        _empresas = empresas;
        _empresaId = id;
      });
      await _carregarUsuarios();
    } on ApiException catch (e) {
      if (e.aparelhoBloqueado) {
        await widget.state.aparelhoRecusado();
        return;
      }
      if (mounted) setState(() => _erro = e.message);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _carregarUsuarios() async {
    final id = _empresaId;
    if (id == null) return;
    final lista = (await widget.state.api.usuarios(id)).cast<Map<String, dynamic>>();
    final anterior = widget.state.config.userId;
    setState(() {
      _usuarios = lista;
      _userId = lista.any((u) => u['id'] == anterior) ? anterior : null;
    });
  }

  Future<void> _entrar() async {
    if (_empresaId == null || _userId == null || _senha.text.isEmpty) {
      avisar(context, 'Escolha o garçom e informe a senha do app.', erro: true);
      return;
    }
    setState(() => _entrando = true);
    try {
      await widget.state.entrar(empresaId: _empresaId!, userId: _userId!, senha: _senha.text);
    } on ApiException catch (e) {
      if (e.aparelhoBloqueado) {
        await widget.state.aparelhoRecusado();
        return;
      }
      if (mounted) avisar(context, e.message, erro: true);
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrar'),
        actions: [
          IconButton(
            tooltip: 'Trocar servidor',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () async {
              if (await confirmar(context, 'Trocar servidor', 'Voltar para a tela de conexão?')) {
                widget.state.trocarServidor();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: [
                if (_erro != null) ...[
                  Text(_erro!, style: TextStyle(color: cs.error)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                      onPressed: _carregar, icon: const Icon(Icons.refresh), label: const Text('Tentar de novo')),
                  const SizedBox(height: 16),
                ],
                if (_empresas.length > 1) ...[
                  DropdownButtonFormField<int>(
                    initialValue: _empresaId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Empresa'),
                    items: [
                      for (final e in _empresas)
                        DropdownMenuItem(value: (e['id'] as num).toInt(), child: Text('${e['nome']}')),
                    ],
                    onChanged: (v) async {
                      setState(() {
                        _empresaId = v;
                        _userId = null;
                      });
                      try {
                        await _carregarUsuarios();
                      } on ApiException catch (e) {
                        if (context.mounted) avisar(context, e.message, erro: true);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<int>(
                  key: ValueKey('usuarios-$_empresaId-${_usuarios.length}'),
                  initialValue: _userId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Garçom', prefixIcon: Icon(Icons.person_outline)),
                  items: [
                    for (final u in _usuarios)
                      DropdownMenuItem(value: (u['id'] as num).toInt(), child: Text('${u['name']}')),
                  ],
                  onChanged: (v) => setState(() => _userId = v),
                ),
                if (_usuarios.isEmpty && _erro == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Nenhum usuário com o app Mesas liberado. No ERP: Usuários → Apps liberados → Mesas, e cadastre a senha do app.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 14),
                TextField(
                  controller: _senha,
                  obscureText: true,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: const InputDecoration(labelText: 'Senha do app', prefixIcon: Icon(Icons.lock_outline)),
                  onSubmitted: (_) => _entrar(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _entrando ? null : _entrar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(_entrando ? 'Entrando…' : 'Entrar'),
                  ),
                ),
              ]),
      ),
    );
  }
}
