import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../domain/chat.dart';
import '../domain/chat_message.dart';
import '../supabase/supabase_providers.dart';
import 'chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return ChatRepository(functions: supabase?.functions, storage: supabase?.storage);
});

/// Bandeja de [uid] (sus conversaciones, la más reciente primero).
final userChatsProvider = StreamProvider.autoDispose.family<List<Chat>, String>(
  (ref, uid) => ref.watch(chatRepositoryProvider).watchUserChats(uid),
  retry: (_, __) => null,
);

/// Una conversación, o null si no existe.
final chatProvider = StreamProvider.autoDispose.family<Chat?, String>(
  (ref, chatId) => ref.watch(chatRepositoryProvider).watchChat(chatId),
  retry: (_, __) => null,
);

/// Los últimos mensajes de una conversación:
/// `chatMessagesProvider((chatId: id, limit: 30))`. "Cargar anteriores" =
/// volver a pedir con un límite mayor (60, 90…).
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, ({String chatId, int limit})>(
  (ref, q) => ref.watch(chatRepositoryProvider).watchMessages(q.chatId, limit: q.limit),
  retry: (_, __) => null,
);

/// Contador de la pestaña "Mensajes": mensajes sin leer del usuario en todas
/// sus conversaciones.
final unreadMessagesCountProvider = Provider.autoDispose<int>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return 0;
  final chats = ref.watch(userChatsProvider(uid)).value ?? const <Chat>[];
  return chats.fold(0, (total, chat) => total + chat.unreadFor(uid));
});
