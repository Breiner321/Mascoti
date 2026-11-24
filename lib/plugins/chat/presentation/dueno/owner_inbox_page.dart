import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/chat_providers.dart';
import '../../../../core/domain/chat.dart';
import '../../../../core/theme/app_theme.dart';
import '../../chat_routes.dart';
import '../comun/conversation_providers.dart';
import 'owner_chat_tile.dart';

/// Pestaña "Mensajes" del dueño (RF-15): conversaciones con sus clínicas,
/// la más reciente primero, con no leídos.
class OwnerInboxPage extends ConsumerWidget {
  const OwnerInboxPage({super.key});

  static const emptyText = 'Aún no tienes conversaciones. Escríbele a una clínica desde su '
      'perfil o desde una cita';

  /// La más reciente primero; las que aún no tienen hora del servidor
  /// (recién creadas) arriba.
  static List<Chat> sorted(List<Chat> chats) => [...chats]..sort((a, b) {
      final at = a.lastMessageAt, bt = b.lastMessageAt;
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return bt.compareTo(at);
    });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid;
    if (uid == null) return const Center(child: CircularProgressIndicator());
    final chats = ref.watch(userChatsProvider(uid));
    final now = ref.read(chatClockProvider)();
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Mensajes',
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: switch (chats) {
            AsyncData(:final value) when value.isEmpty => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 56, color: AppColors.primary),
                      const SizedBox(height: 12),
                      Text(emptyText, textAlign: TextAlign.center, style: textTheme.bodyLarge),
                    ],
                  ),
                ),
              ),
            AsyncData(:final value) => ListView.separated(
                itemCount: value.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                itemBuilder: (context, i) {
                  final chat = sorted(value)[i];
                  return OwnerChatTile(
                    key: ValueKey(chat.id),
                    chat: chat,
                    uid: uid,
                    now: now,
                    onTap: () => context.push(ChatRoutes.conversation(chat.id)),
                  );
                },
              ),
            AsyncError() => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No se pudieron cargar tus mensajes.'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref.invalidate(userChatsProvider(uid)),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}
