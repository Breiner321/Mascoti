import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/images/photo_compression.dart';
import '../../../../core/theme/app_theme.dart';
import 'product_thumbnail.dart';

/// Foto del formulario de producto: muestra la foto actual o la recién
/// elegida y abre una hoja para tomarla con la cámara o elegirla de la
/// galería. [errorText] aparece debajo (foto obligatoria o archivo no
/// válido).
class ProductPhotoField extends StatelessWidget {
  const ProductPhotoField({
    super.key,
    required this.photoPath,
    required this.bytes,
    required this.processing,
    required this.onPick,
    this.errorText,
    this.enabled = true,
  });

  final String? photoPath;
  final Uint8List? bytes;

  /// true mientras se comprime la foto elegida.
  final bool processing;
  final ValueChanged<PhotoSource> onPick;
  final String? errorText;
  final bool enabled;

  Future<void> _chooseSource(BuildContext context) async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) onPick(source);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhoto = bytes != null || (photoPath?.isNotEmpty ?? false);
    final canPick = enabled && !processing;
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: canPick ? () => _chooseSource(context) : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ProductThumbnail(photoPath: photoPath, bytes: bytes, size: 120),
              if (processing) const CircularProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (processing)
          Text(
            'Comprimiendo foto…',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          )
        else
          TextButton.icon(
            onPressed: canPick ? () => _chooseSource(context) : null,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(hasPhoto ? 'Cambiar foto' : 'Agregar foto'),
          ),
        if (errorText != null)
          Text(
            errorText!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
      ],
    );
  }
}
