import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/medical_record.dart';
import '../../../../core/theme/app_theme.dart';
import '../attachment_viewer_page.dart';
import '../pets_providers.dart';

/// Adjunto de una consulta. Pide su enlace temporal por separado: si falla
/// (o la imagen no carga) muestra "Archivo no disponible" sin afectar al
/// resto del historial (RF-08).
class RecordAttachmentTile extends ConsumerWidget {
  const RecordAttachmentTile({super.key, required this.petId, required this.attachment});

  final String petId;
  final RecordAttachment attachment;

  Future<void> _openPdf(BuildContext context, WidgetRef ref, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await ref.read(externalUrlOpenerProvider)(Uri.parse(url));
    } catch (_) {}
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el PDF en este teléfono')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(recordAttachmentUrlProvider((petId, attachment.path)));
    final isPdf = attachment.tipo == AttachmentType.pdf;

    return switch (url) {
      AsyncData(:final value) when isPdf => _Tile(
          icon: Icons.picture_as_pdf_outlined,
          title: attachment.nombre,
          subtitle: 'PDF · toca para abrir o descargar',
          onTap: () => _openPdf(context, ref, value),
        ),
      AsyncData(:final value) => _Tile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              value,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _UnavailableIcon(),
            ),
          ),
          title: attachment.nombre,
          subtitle: 'Imagen · toca para verla completa',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => AttachmentViewerPage(title: attachment.nombre, url: value),
          )),
        ),
      AsyncError() => _Tile(
          leading: const _UnavailableIcon(),
          title: attachment.nombre,
          subtitle: 'Archivo no disponible',
          trailing: IconButton(
            tooltip: 'Reintentar',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(recordAttachmentUrlProvider((petId, attachment.path))),
          ),
        ),
      _ => _Tile(
          leading: const SizedBox(
            width: 48,
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          title: attachment.nombre,
          subtitle: 'Cargando…',
        ),
    };
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: leading ??
            SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: AppColors.primary, size: 32),
            ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

/// Ícono de "Archivo no disponible".
class _UnavailableIcon extends StatelessWidget {
  const _UnavailableIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Tooltip(
        message: 'Archivo no disponible',
        child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 32),
      ),
    );
  }
}
