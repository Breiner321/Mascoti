import 'package:flutter/material.dart';

import '../../../../core/domain/chat_message.dart';
import '../../../../core/theme/app_theme.dart';
import 'chat_grouping.dart';

/// Burbuja de un mensaje (RF-15): propias a la derecha (morado) y ajenas a
/// la izquierda, con la hora y, en las propias, el estado con ícono:
/// reloj (enviando), ✓ (enviado) y ✓✓ (leído).
///
/// TalkBack la lee completa en una sola frase ([bubbleSemantics]). Si el
/// mensaje es un adjunto, [attachment] (de RF-16) va dentro y conserva sus
/// propios botones (abrir, reintentar).
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.otherName,
    required this.now,
    this.attachment,
  });

  final ChatMessage message;
  final bool mine;
  final String otherName;
  final DateTime now;

  /// Vista del archivo adjunto (RF-16, Dev B); null en los de texto.
  final Widget? attachment;

  static IconData statusIcon(MessageStatus status) => switch (status) {
        MessageStatus.sending => Icons.schedule,
        MessageStatus.sent => Icons.done,
        MessageStatus.read => Icons.done_all,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = mine ? AppColors.onPrimary : AppColors.textPrimary;
    final meta = textTheme.labelSmall?.copyWith(color: foreground.withValues(alpha: 0.85));
    final status = MessageStatus.of(message);
    final text = message.texto.trim();
    final label = bubbleSemantics(message: message, mine: mine, otherName: otherName, now: now);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // El adjunto (RF-16) muestra su propio comentario.
        if (attachment != null) attachment!,
        if (attachment == null && text.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(text, style: textTheme.bodyMedium?.copyWith(color: foreground)),
          ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(timeLabel(message.timestamp ?? now), style: meta),
            if (mine) ...[
              const SizedBox(width: 4),
              Icon(statusIcon(status), size: 16, color: foreground),
            ],
          ],
        ),
      ],
    );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
      decoration: BoxDecoration(
        color: mine ? AppColors.primary : AppColors.surface,
        border: mine ? null : Border.all(color: AppColors.border),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: content,
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      // Texto: una sola frase. Adjunto: la frase y, aparte, sus botones.
      child: attachment == null
          ? Semantics(container: true, label: label, excludeSemantics: true, child: bubble)
          : Semantics(container: true, label: label, child: bubble),
    );
  }
}

/// Separador "Hoy", "Ayer", "lun 9 nov".
class DaySeparator extends StatelessWidget {
  const DaySeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
