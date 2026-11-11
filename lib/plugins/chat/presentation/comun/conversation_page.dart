import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/chat_providers.dart';
import '../../../../core/data/chat_repository.dart';
import '../../../../core/domain/chat.dart';
import '../../../../core/domain/chat_message.dart';

/// Conversación a pantalla completa (`/chat/:chatId`, RF-15).
///
/// PROVISIONAL (semana 5, Dev A): versión mínima para probar el núcleo
/// (mensajes en tiempo real, enviar, leídos y "escribiendo…"). La reemplaza
/// el Dev C (burbujas, "Enviando…", doble check, adjuntos con el Dev B).
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final _text = TextEditingController();
  late final TypingController _typing;
  String? _lastReadId;

  @override
  void initState() {
    super.initState();
    _typing = TypingController(
      write: (typing) => ref.read(chatRepositoryProvider).setTyping(
            chatId: widget.chatId,
            uid: ref.read(currentUserProvider)!.uid,
            typing: typing,
          ),
    );
  }

  @override
  void dispose() {
    _typing.dispose();
    _text.dispose();
    super.dispose();
  }

  void _markRead(Chat chat, List<ChatMessage> messages, String uid) {
    final last = messages.isEmpty ? null : messages.last.id;
    if (last == _lastReadId && chat.unreadFor(uid) == 0) return;
    _lastReadId = last;
    ref.read(chatRepositoryProvider).markAsRead(chat: chat, uid: uid).ignore();
  }

  void _send(Chat chat, String uid) {
    try {
      ref.read(chatRepositoryProvider).sendText(chat: chat, senderUid: uid, text: _text.text);
      _text.clear();
      _typing.stop();
    } on ChatFailure catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserProvider)?.uid;
    final chat = ref.watch(chatProvider(widget.chatId)).value;
    final messages = ref.watch(
      chatMessagesProvider((chatId: widget.chatId, limit: ChatLimits.pageSize)),
    );
    if (uid == null || chat == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mensajes')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final list = messages.value;
    if (list != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markRead(chat, list, uid);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chat.otherName(uid)),
            if (chat.isOtherTyping(uid, DateTime.now().toUtc()))
              Text('escribiendo…', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: FilledButton(
                  onPressed: () => ref.invalidate(chatMessagesProvider),
                  child: const Text('Reintentar'),
                ),
              ),
              data: (items) => items.isEmpty
                  ? const Center(child: Text('Escribe el primer mensaje.'))
                  : ListView(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final m in items.reversed)
                          Align(
                            alignment:
                                m.isMine(uid) ? Alignment.centerRight : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                [
                                  m.tipo == ChatMessageType.adjunto
                                      ? '📎 ${m.adjunto?.nombre ?? ''}'
                                      : m.texto,
                                  if (m.pendiente) '(Enviando…)',
                                  if (m.isMine(uid) && m.leido) '(Leído)',
                                ].join(' '),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: ChatLimits.maxText,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: _typing.onTextChanged,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Enviar',
                    icon: const Icon(Icons.send),
                    onPressed: () => _send(chat, uid),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
