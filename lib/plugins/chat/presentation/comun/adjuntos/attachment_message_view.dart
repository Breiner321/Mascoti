import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/attachments/attachment_status.dart';
import '../../../../../core/attachments/attachment_viewer_page.dart';
import '../../../../../core/domain/chat_message.dart';
import '../../../../../core/theme/app_theme.dart';
import '../chat_ui_providers.dart';
import 'file_bubble.dart';
import 'history_reference.dart';

/// Mensaje tipo adjunto ya enviado (RF-16 pasos 7–8): miniatura de la
/// imagen o ícono de PDF con el nombre. Al tocarlo, la imagen se abre en
/// pantalla completa con zoom y el PDF en el visor del teléfono.
///
/// El enlace (15 min) se pide a `adjuntos-chat`; si venció o la imagen no
/// carga, se pide otro sin avisar. Si vuelve a fallar: "Archivo no
/// disponible" (tocar lo intenta de nuevo).
class AttachmentMessageView extends ConsumerStatefulWidget {
  const AttachmentMessageView({
    super.key,
    required this.chatId,
    required this.message,
    required this.mine,
  });

  static const unavailable = 'Archivo no disponible';

  final String chatId;
  final ChatMessage message;
  final bool mine;

  @override
  ConsumerState<AttachmentMessageView> createState() => _AttachmentMessageViewState();
}

class _AttachmentMessageViewState extends ConsumerState<AttachmentMessageView> {
  String? _thumbUrl;
  bool _unavailable = false;
  bool _refreshedOnce = false;
  bool _opening = false;

  ChatAttachment get _adjunto => widget.message.adjunto!;
  bool get _isImage => _adjunto.tipo == ChatAttachmentType.imagen;

  @override
  void initState() {
    super.initState();
    if (_isImage) _loadThumb();
  }

  Future<String> _url({bool refresh = false}) => ref
      .read(attachmentLinkCacheProvider)
      .url(chatId: widget.chatId, path: _adjunto.path, refresh: refresh);

  Future<void> _loadThumb({bool refresh = false}) async {
    try {
      final url = await _url(refresh: refresh);
      if (mounted) setState(() => _thumbUrl = url);
    } catch (_) {
      if (refresh || _refreshedOnce) {
        if (mounted) setState(() => _unavailable = true);
      } else {
        _refreshedOnce = true;
        await _loadThumb(refresh: true);
      }
    }
  }

  /// La miniatura no cargó: un enlace nuevo una vez; si tampoco, no está.
  void _onThumbError() {
    if (_unavailable) return;
    if (_refreshedOnce) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _unavailable = true);
      });
      return;
    }
    _refreshedOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadThumb(refresh: true));
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      String url;
      try {
        url = await _url();
      } catch (_) {
        url = await _url(refresh: true);
      }
      if (!mounted) return;
      setState(() => _unavailable = false);
      if (_isImage) {
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => AttachmentViewerPage(title: _adjunto.nombre, url: url),
        ));
      } else {
        var opened = false;
        try {
          opened = await ref.read(chatUrlOpenerProvider)(Uri.parse(url));
        } catch (_) {}
        if (!opened) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No se pudo abrir el PDF en este teléfono')),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
      messenger.showSnackBar(const SnackBar(content: Text(AttachmentMessageView.unavailable)));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = HistoryReference.parse(widget.message.referenciaHistorialId);
    String? label;
    if (reference != null) {
      final pet = ref.watch(chatPetProvider(reference.petId)).value;
      label = pet == null || pet.nombre.isEmpty
          ? 'Del historial médico'
          : 'Del historial médico de ${pet.nombre}';
    }

    Widget? preview;
    if (_unavailable) {
      preview = Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 32);
    } else if (_opening) {
      preview = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_isImage) {
      final url = _thumbUrl;
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: url == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Image.network(
                url,
                key: ValueKey(url),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  _onThumbError();
                  return Icon(Icons.image_outlined, color: AppColors.textMuted, size: 32);
                },
              ),
      );
    }

    final bubble = FileBubble(
      nombre: _adjunto.nombre,
      tipo: _adjunto.tipo,
      status: AttachmentStatus.done,
      mine: widget.mine,
      label: label,
      preview: preview,
      subtitle: _unavailable ? AttachmentMessageView.unavailable : null,
      onOpen: _open,
    );
    final comment = widget.message.texto.trim();
    if (comment.isEmpty) return bubble;
    return Column(
      crossAxisAlignment: widget.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(comment)),
      ],
    );
  }
}
