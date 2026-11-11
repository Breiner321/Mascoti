import 'package:flutter/material.dart';

import '../comun/chat_list_view.dart';

/// Bandeja de mensajes del dueño (RF-15).
///
/// PROVISIONAL (semana 5, Dev A): la reemplaza el Dev C.
class OwnerInboxPage extends StatelessWidget {
  const OwnerInboxPage({super.key});

  @override
  Widget build(BuildContext context) => const ChatListView(
        emptyMessage: 'Aún no tienes conversaciones. Escríbele a una clínica desde el detalle '
            'de una cita o desde su perfil.',
      );
}
