import 'package:flutter/material.dart';

import '../core/modelos.dart';
import '../core/sync.dart';

/// Conectado / Offline + pendentes (canto da barra superior).
class StatusConexao extends StatelessWidget {
  const StatusConexao({super.key, required this.sync, this.onTap});

  final SyncService sync;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final online = sync.online;
        final (cor, texto, icone) = switch (online) {
          true => (const Color(0xFF15803D), 'Conectado', Icons.wifi),
          false => (const Color(0xFFB91C1C), 'Offline', Icons.wifi_off),
          null => (Colors.grey, 'Verificando', Icons.sync),
        };

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icone, size: 16, color: cor),
              const SizedBox(width: 4),
              Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
              if (sync.pendentes > 0) ...[
                const SizedBox(width: 6),
                _Contador(valor: sync.pendentes, cor: const Color(0xFFD97706), enviando: sync.enviando),
              ],
              if (sync.erros > 0) ...[
                const SizedBox(width: 4),
                _Contador(valor: sync.erros, cor: const Color(0xFFB91C1C)),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador({required this.valor, required this.cor, this.enviando = false});

  final int valor;
  final Color cor;
  final bool enviando;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(10)),
      child: Text(
        enviando ? '$valor ↑' : '$valor',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Selo do pedido: Pendente / Enviado / Erro.
class SeloPedido extends StatelessWidget {
  const SeloPedido({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (cor, texto) = switch (status) {
      StatusPedido.enviado => (const Color(0xFF15803D), 'Enviado'),
      StatusPedido.erro => (const Color(0xFFB91C1C), 'Erro'),
      _ => (const Color(0xFFD97706), 'Pendente'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(texto, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

void avisar(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? const Color(0xFFB91C1C) : null,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
}

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String ok = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}
