import 'package:flutter/material.dart';

import '../../../../../core/attachments/attachment_status.dart';
import '../../../../../core/domain/chat_message.dart';
import '../../../../../core/theme/app_theme.dart';

/// Burbuja de un archivo del chat (RF-16) en sus tres estados:
/// - subiendo: barra de progreso;
/// - error: el mensaje y "Reintentar" (el resto del chat sigue funcionando);
/// - listo: miniatura o ícono de PDF con el nombre; al tocarla se abre.
///
/// [label] es la etiqueta de origen ("Del historial médico de Luna").
class FileBubble extends StatelessWidget {
  const FileBubble({
    super.key,
    required this.nombre,
    required this.tipo,
    required this.status,
    this.mine = true,
    this.error,
    this.label,
    this.preview,
    this.subtitle,
    this.onOpen,
    this.onRetry,
    this.onDiscard,
  });

  final String nombre;
  final ChatAttachmentType tipo;
  final AttachmentStatus status;
  final bool mine;
  final String? error;
  final String? label;

  /// Miniatura de la imagen (si no hay, un ícono según el tipo).
  final Widget? preview;

  /// Reemplaza el texto bajo el nombre en el estado "listo".
  final String? subtitle;
  final VoidCallback? onOpen;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  bool get _isPdf => tipo == ChatAttachmentType.pdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = status == AttachmentStatus.failed;
    final uploading = status == AttachmentStatus.uploading;
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted);

    final detail = switch (status) {
      AttachmentStatus.uploading => 'Subiendo…',
      AttachmentStatus.failed => error ?? 'Error al enviar archivo',
      AttachmentStatus.done =>
        subtitle ?? (_isPdf ? 'PDF · toca para abrir' : 'Imagen · toca para verla'),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Material(
        color: failed
            ? AppColors.sosContainer
            : (mine ? AppColors.primaryContainer : AppColors.surface),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: failed ? AppColors.sosBorder : AppColors.border),
        ),
        child: InkWell(
          onTap: status == AttachmentStatus.done ? onOpen : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label case final text?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Row(
                    children: [
                      Icon(Icons.medical_information_outlined, size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          text,
                          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: preview ??
                          Icon(
                            _isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                            color: failed ? AppColors.sos : AppColors.primary,
                            size: 32,
                          ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text(
                            detail,
                            style: failed ? muted?.copyWith(color: AppColors.sos) : muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (uploading)
                const LinearProgressIndicator(
                  minHeight: 3,
                  semanticsLabel: 'Subiendo archivo',
                ),
              if (failed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  // Wrap: con letra grande los dos botones bajan de línea.
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      if (onDiscard != null)
                        TextButton(onPressed: onDiscard, child: const Text('Descartar')),
                      if (onRetry != null)
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
