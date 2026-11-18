import 'package:flutter/material.dart';

import '../../../../core/domain/chat.dart';
import '../../../../core/domain/chat_message.dart';
import '../../../../core/theme/app_theme.dart';
import '../comun/chat_avatar.dart';
import '../comun/chat_grouping.dart';

/// Conversación en la bandeja del dueño: iniciales y nombre de la clínica,
/// vista previa del último mensaje, hora y no leídos.
class OwnerChatTile extends StatelessWidget {
  const OwnerChatTile({
    super.key,
    required this.chat,
    required this.uid,
    required this.now,
    required this.onTap,
  });

  final Chat chat;
  final String uid;
  final DateTime now;
  final VoidCallback onTap;

  /// "Tú: Gracias", "📎 examen.pdf" o "Sin mensajes".
  static String preview(Chat chat, String uid) {
    final last = chat.lastMessage;
    if (last == null) return 'Sin mensajes';
    final body = last.tipo == ChatMessageType.adjunto ? 'Archivo: ${last.texto}' : last.texto;
    return last.senderUid == uid ? 'Tú: $body' : body;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final unread = chat.unreadFor(uid);
    final name = chat.clinicNombre.isEmpty ? 'Clínica' : chat.clinicNombre;
    final time = inboxTimeLabel(chat.lastMessageAt, now);
    final text = preview(chat, uid);
    final semantics = [
      name,
      text,
      if (time.isNotEmpty) time,
      if (unread > 0) unread == 1 ? '1 mensaje sin leer' : '$unread mensajes sin leer',
    ].join(', ');

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ChatAvatar(name: name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: unread > 0 ? AppColors.textPrimary : AppColors.textMuted,
                        fontWeight: unread > 0 ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(time, style: textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
                  if (unread > 0) ...[
                    const SizedBox(height: 4),
                    Badge(label: Text(unread > 99 ? '99+' : '$unread')),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
