import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_uploads_controller.dart';
import 'file_bubble.dart';

/// Burbujas de los archivos que se están enviando a la conversación (con
/// progreso o "Reintentar"), alineadas como mensajes propios. Va al final de
/// la lista de mensajes.
class PendingUploadsView extends ConsumerWidget {
  const PendingUploadsView({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploads = ref.watch(chatUploadsProvider(chatId));
    if (uploads.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(chatUploadsProvider(chatId).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final u in uploads)
          Padding(
            key: ValueKey(u.id),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: FileBubble(
              nombre: u.nombre,
              tipo: u.tipo,
              status: u.status,
              error: u.error,
              label: u.referenciaHistorialId == null ? null : 'Del historial médico',
              onRetry: () => controller.retry(u.id),
              onDiscard: () => controller.discard(u.id),
            ),
          ),
      ],
    );
  }
}
