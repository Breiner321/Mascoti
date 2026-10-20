import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/domain/medical_record.dart';
import '../../../core/theme/app_theme.dart';

enum AttachmentStatus { uploading, done, failed }

/// Adjunto del formulario de consulta: uno ya guardado o uno que se está
/// subiendo (con su estado y el error si falló).
class AttachmentDraft {
  AttachmentDraft.picked({required this.nombre, required Uint8List this.bytes, required this.tipo})
      : status = AttachmentStatus.uploading;

  AttachmentDraft.saved(RecordAttachment this.saved)
      : nombre = saved.nombre,
        tipo = saved.tipo,
        bytes = null,
        status = AttachmentStatus.done;

  final Key key = UniqueKey();
  final String nombre;
  final AttachmentType tipo;

  /// Contenido del archivo recién elegido (para reintentar y previsualizar).
  final Uint8List? bytes;
  AttachmentStatus status;
  RecordAttachment? saved;
  String? error;
}

/// Fila de un adjunto: ícono según el tipo, progreso mientras sube y
/// "Reintentar" si falló.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.draft,
    required this.readOnly,
    required this.onRetry,
    required this.onRemove,
    required this.onOpen,
  });

  final AttachmentDraft draft;
  final bool readOnly;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = draft.status == AttachmentStatus.failed;
    final uploading = draft.status == AttachmentStatus.uploading;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: failed ? AppColors.sosContainer : AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: failed ? AppColors.sosBorder : AppColors.border),
        ),
        child: Column(
          children: [
            ListTile(
              onTap: draft.status == AttachmentStatus.done ? onOpen : null,
              leading: Icon(
                draft.tipo == AttachmentType.pdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
                color: failed ? AppColors.sos : AppColors.primary,
              ),
              title: Text(draft.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                switch (draft.status) {
                  AttachmentStatus.uploading => 'Subiendo…',
                  AttachmentStatus.done => draft.tipo == AttachmentType.pdf ? 'PDF' : 'Imagen',
                  AttachmentStatus.failed => draft.error ?? 'No se pudo subir el archivo',
                },
                style: failed ? theme.textTheme.bodySmall?.copyWith(color: AppColors.sos) : null,
              ),
              trailing: readOnly
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (failed && draft.bytes != null)
                          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
                        if (!uploading)
                          IconButton(
                            tooltip: 'Quitar adjunto',
                            icon: const Icon(Icons.close),
                            onPressed: onRemove,
                          ),
                      ],
                    ),
            ),
            if (uploading) const LinearProgressIndicator(minHeight: 3),
          ],
        ),
      ),
    );
  }
}
