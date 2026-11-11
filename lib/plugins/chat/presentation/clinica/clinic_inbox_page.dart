import 'package:flutter/material.dart';

import '../comun/chat_list_view.dart';

/// Bandeja de mensajes de la clínica (RF-15).
///
/// PROVISIONAL (semana 5, Dev A): la reemplaza el Dev B.
class ClinicInboxPage extends StatelessWidget {
  const ClinicInboxPage({super.key});

  @override
  Widget build(BuildContext context) => const ChatListView(
        emptyMessage: 'Aún no tienes conversaciones con tus clientes.',
      );
}
