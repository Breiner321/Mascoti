import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/chat_providers.dart';
import '../../chat_routes.dart';

/// PROVISIONAL (semana 5, Dev A): lista mínima de conversaciones del usuario
/// para probar el núcleo del chat. La reemplazan las bandejas del dueño
/// (Dev C) y de la clínica (Dev B).
class ChatListView extends ConsumerWidget {
  const ChatListView({super.key, required this.emptyMessage});

  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid;
    if (uid == null) return const Center(child: CircularProgressIndicator());
    final chats = ref.watch(userChatsProvider(uid));
    return chats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
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
      data: (list) => list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(emptyMessage, textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final chat = list[i];
                final unread = chat.unreadFor(uid);
                return ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(chat.otherName(uid)),
                  subtitle: Text(
                    chat.lastMessage?.texto ?? 'Sin mensajes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: unread > 0
                      ? Semantics(
                          label: '$unread sin leer',
                          excludeSemantics: true,
                          child: Badge(label: Text('$unread')),
                        )
                      : null,
                  onTap: () => context.push(ChatRoutes.conversation(chat.id)),
                );
              },
            ),
    );
  }
}
