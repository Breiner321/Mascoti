import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/attachments/attachment_picker.dart';
import '../../../../../core/data/chat_repository.dart';
import '../../../../../core/data/medical_records_providers.dart';
import '../../../../../core/domain/chat.dart';
import '../../../../../core/domain/chat_message.dart';
import '../../../../../core/domain/medical_record.dart';
import '../chat_ui_providers.dart';
import 'attachment_prep.dart';
import 'chat_uploads_controller.dart';
import 'history_attachment_page.dart';
import 'history_reference.dart';

enum _AttachOption { image, pdf, history }

/// Botón de clip de la conversación (RF-16): "Foto o imagen", "Documento
/// PDF" y, solo para la clínica, "Desde el historial". El archivo se valida
/// y se comprime aquí; la subida sigue en [chatUploadsProvider] sin
/// bloquear el chat.
class AttachButton extends ConsumerWidget {
  const AttachButton({super.key, required this.chat, required this.uid});

  final Chat chat;
  final String uid;

  bool get _isClinic => uid == chat.clinicOwnerUid;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final option = await showModalBottomSheet<_AttachOption>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Foto o imagen'),
              subtitle: const Text('JPG o PNG, máximo 10 MB'),
              onTap: () => Navigator.pop(context, _AttachOption.image),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Documento PDF'),
              subtitle: const Text('Máximo 10 MB'),
              onTap: () => Navigator.pop(context, _AttachOption.pdf),
            ),
            if (_isClinic)
              ListTile(
                leading: const Icon(Icons.medical_information_outlined),
                title: const Text('Desde el historial'),
                subtitle: const Text('Radiografías, exámenes y otros archivos de una consulta'),
                onTap: () => Navigator.pop(context, _AttachOption.history),
              ),
          ],
        ),
      ),
    );
    if (option == null || !context.mounted) return;
    switch (option) {
      case _AttachOption.image:
        await _sendPicked(context, ref, (p) => p.pickImage());
      case _AttachOption.pdf:
        await _sendPicked(context, ref, (p) => p.pickPdf());
      case _AttachOption.history:
        await _sendFromHistory(context, ref);
    }
  }

  Future<void> _sendPicked(
    BuildContext context,
    WidgetRef ref,
    Future<PickedFile?> Function(AttachmentPicker picker) pick,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ref.read(chatAttachmentPickerProvider);
    final compress = ref.read(imageCompressorProvider);
    final uploads = ref.read(chatUploadsProvider(chat.id).notifier);
    try {
      final file = await pick(picker);
      if (file == null) return;
      final prepared = await prepareChatAttachment(file.name, file.bytes, compress: compress);
      uploads.send(
            chat: chat,
            senderUid: uid,
            nombre: prepared.name,
            tipo: prepared.tipo,
            source: () async => prepared.bytes,
          );
    } on ChatFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el archivo. Intenta con otro.')),
      );
    }
  }

  Future<void> _sendFromHistory(BuildContext context, WidgetRef ref) async {
    final selection = await Navigator.of(context).push<HistorySelection>(
      MaterialPageRoute(builder: (_) => HistoryAttachmentPage(chat: chat)),
    );
    if (selection == null || !context.mounted) return;
    final attachment = selection.attachment;
    final nombre = historyFileName(attachment);
    // Se leen ahora: la subida (y sus reintentos) puede seguir después de
    // cerrar la conversación.
    final records = ref.read(medicalRecordsRepositoryProvider);
    final download = ref.read(fileDownloaderProvider);
    ref.read(chatUploadsProvider(chat.id).notifier).send(
          chat: chat,
          senderUid: uid,
          nombre: nombre,
          tipo: attachment.tipo == AttachmentType.pdf
              ? ChatAttachmentType.pdf
              : ChatAttachmentType.imagen,
          referenciaHistorialId:
              HistoryReference(petId: selection.pet.id, recordId: selection.record.id).value,
          // Se baja del bucket del historial y se sube al del chat: así el
          // dueño lo abre como cualquier otro adjunto.
          source: () async {
            final url =
                await records.attachmentUrl(petId: selection.pet.id, path: attachment.path);
            final bytes = await download(Uri.parse(url));
            ChatRepository.validateFile(nombre, bytes.length);
            return bytes;
          },
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: 'Adjuntar',
        icon: const Icon(Icons.attach_file),
        onPressed: () => _choose(context, ref),
      );
}

/// Nombre con el que se envía un adjunto del historial: el original, con
/// extensión (la necesitan la validación y `adjuntos-chat`).
String historyFileName(RecordAttachment attachment) {
  final name = attachment.nombre.trim().isEmpty ? 'archivo' : attachment.nombre.trim();
  if (ChatAttachmentType.fromFileName(name) != null) return name;
  return attachment.tipo == AttachmentType.pdf ? '$name.pdf' : '$name.jpg';
}
