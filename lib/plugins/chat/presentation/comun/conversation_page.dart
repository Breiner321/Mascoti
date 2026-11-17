import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/chat_providers.dart';
import '../../../../core/data/chat_repository.dart';
import '../../../../core/domain/chat.dart';
import '../../../../core/domain/chat_message.dart';
import '../../../../core/theme/app_theme.dart';
import 'adjuntos/attach_button.dart';
import 'adjuntos/attachment_message_view.dart';
import 'adjuntos/chat_uploads_controller.dart';
import 'adjuntos/pending_uploads_view.dart';
import 'chat_avatar.dart';
import 'chat_grouping.dart';
import 'chat_ui_providers.dart';
import 'conversation_providers.dart';
import 'message_bubble.dart';

/// Conversación a pantalla completa (`/chat/:chatId`, RF-15), la misma para
/// el dueño y la clínica.
///
/// Enviar no espera al servidor: el mensaje aparece de inmediato con el reloj
/// y Firestore lo envía solo al volver la red; `ChatRepository` llama a
/// `notificar-mensaje` cuando el servidor lo confirma.
///
/// Adjuntos (RF-16, Dev B): ver [_ConversationPageState._attachButton],
/// [_ConversationPageState._attachmentOf] y [PendingUploadsView] en la lista.
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key, required this.chatId});

  final String chatId;

  static const offlineNotice = 'Sin conexión, se enviará cuando vuelva la red';
  static const emptyText = 'Aún no hay mensajes. Escribe el primero.';

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final TypingController _typing;
  String? _lastReadId;

  /// Mensajes que se escuchan en tiempo real; "Cargar mensajes anteriores"
  /// lo amplía (los viejos siguen recibiendo el doble check).
  int _limit = ChatLimits.pageSize;

  /// Envíos sin confirmar y si ya se avisó que no hay conexión.
  int _waiting = 0;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    // Se guardan aquí: al salir, dispose() borra "escribiendo…" y ya no se
    // puede usar `ref`.
    final repository = ref.read(chatRepositoryProvider);
    final uid = ref.read(currentUserProvider)?.uid;
    _typing = TypingController(
      write: (typing) async {
        if (uid == null) return;
        await repository.setTyping(chatId: widget.chatId, uid: uid, typing: typing);
      },
    );
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typing.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _markRead(Chat chat, List<ChatMessage> messages, String uid) {
    final last = messages.isEmpty ? null : messages.last.id;
    if (last == _lastReadId && chat.unreadFor(uid) == 0) return;
    _lastReadId = last;
    ref.read(chatRepositoryProvider).markAsRead(chat: chat, uid: uid).ignore();
  }

  void _send(Chat chat, String uid) {
    final SentMessage sent;
    try {
      sent = ref.read(chatRepositoryProvider).sendText(chat: chat, senderUid: uid, text: _text.text);
    } on ChatFailure catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    _text.clear();
    _typing.stop();
    _watchDelivery(sent.delivered);
    // Bajar al último mensaje (la lista está invertida: 0 es el final).
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Si el servidor tarda, avisa sin bloquear; el aviso se va al confirmar.
  void _watchDelivery(Future<void> delivered) {
    _waiting++;
    var done = false;
    final timer = Timer(ref.read(offlineNoticeDelayProvider), () {
      if (!done && mounted) setState(() => _offline = true);
    });
    delivered.then((_) {}, onError: (Object _) {}).whenComplete(() {
      done = true;
      timer.cancel();
      _waiting--;
      if (mounted && _waiting == 0 && _offline) setState(() => _offline = false);
    });
  }

  Future<void> _call(String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await ref.read(chatUrlOpenerProvider)(
        Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
      );
    } catch (_) {}
    if (!opened) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir el teléfono')));
    }
  }

  // --- Adjuntos (RF-16, Dev B) ----------------------------------------------
  // Puntos de conexión del clip y de las burbujas de archivo.

  Widget _attachButton(Chat chat, String uid) => AttachButton(chat: chat, uid: uid);

  Widget? _attachmentOf(ChatMessage m, String uid) =>
      m.tipo == ChatMessageType.adjunto && m.adjunto != null
          ? AttachmentMessageView(chatId: widget.chatId, message: m, mine: m.isMine(uid))
          : null;

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final uid = user?.uid;
    final chatValue = ref.watch(chatProvider(widget.chatId));
    final chat = chatValue.value;

    if (uid == null || chat == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mensajes')),
        body: Center(
          child: chatValue.hasError || (chatValue.hasValue && chat == null)
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No pudimos abrir la conversación.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => ref.invalidate(chatProvider(widget.chatId)),
                      child: const Text('Reintentar'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    final now = ref.read(chatClockProvider)();
    final messages = ref.watch(chatMessagesProvider((chatId: widget.chatId, limit: _limit)));
    final list = messages.value;
    if (list != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markRead(chat, list, uid);
      });
    }
    final isOwner = uid == chat.ownerUid;
    final phone = isOwner ? ref.watch(clinicPhoneProvider(chat.clinicId)).value : null;
    final otherName = chat.otherName(uid);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ChatAvatar(name: otherName, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(otherName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (chat.isOtherTyping(uid, now))
                    Text(
                      'escribiendo…',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.primary, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (phone != null)
            IconButton(
              tooltip: 'Llamar',
              icon: const Icon(Icons.call_outlined),
              onPressed: () => _call(phone),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_offline)
            Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: AppColors.slotBlockedContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, size: 18, color: AppColors.slotBlocked),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(ConversationPage.offlineNotice,
                          style: TextStyle(color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: switch (messages) {
              AsyncValue(value: final List<ChatMessage> items) => _messagesList(
                  items: items,
                  uid: uid,
                  otherName: otherName,
                  now: now,
                ),
              AsyncError() => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No pudimos cargar los mensajes.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(chatMessagesProvider),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
          _composer(chat, uid),
        ],
      ),
    );
  }

  Widget _messagesList({
    required List<ChatMessage> items,
    required String uid,
    required String otherName,
    required DateTime now,
  }) {
    final uploading = ref.watch(chatUploadsProvider(widget.chatId)).isNotEmpty;
    if (items.isEmpty && !uploading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            ConversationPage.emptyText,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }
    final grouped = groupByDay(items, now).reversed.toList();
    // Si llegó una página completa, puede haber más antiguos.
    final mayHaveOlder = items.length >= _limit;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: grouped.length + 1 + (mayHaveOlder ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == 0) {
          // Subidas en curso (RF-16) justo encima del campo de texto.
          return Align(
            alignment: Alignment.centerRight,
            child: PendingUploadsView(chatId: widget.chatId),
          );
        }
        final index = i - 1;
        if (index == grouped.length) {
          return Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _limit += ChatLimits.pageSize),
              icon: const Icon(Icons.history),
              label: const Text('Cargar mensajes anteriores'),
            ),
          );
        }
        return switch (grouped[index]) {
          DaySeparatorItem(:final label) => DaySeparator(key: ValueKey('dia-$label'), label: label),
          MessageItem(:final message) => MessageBubble(
              key: ValueKey(message.id),
              message: message,
              mine: message.isMine(uid),
              otherName: otherName,
              now: now,
              attachment: _attachmentOf(message, uid),
            ),
        };
      },
    );
  }

  Widget _composer(Chat chat, String uid) {
    final text = _text.text;
    final canSend = text.trim().isNotEmpty;
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _attachButton(chat, uid),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLength: ChatLimits.maxText,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: _typing.onTextChanged,
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje',
                    // El contador aparece al acercarse a 2000.
                    counterText: showCounter(text) ? null : '',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Enviar',
                icon: const Icon(Icons.send),
                color: AppColors.primary,
                onPressed: canSend ? () => _send(chat, uid) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
