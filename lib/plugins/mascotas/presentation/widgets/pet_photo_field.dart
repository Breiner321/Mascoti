import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/pet_photo_service.dart';
import '../../domain/pet_photo.dart';
import 'pet_avatar.dart';

/// Foto del formulario: muestra la foto actual o la recién elegida y abre
/// una hoja para tomarla con la cámara o elegirla de la galería.
class PetPhotoField extends StatelessWidget {
  const PetPhotoField({
    super.key,
    required this.photoPath,
    required this.photo,
    required this.processing,
    required this.onPick,
    this.enabled = true,
  });

  final String? photoPath;
  final PetPhoto? photo;

  /// true mientras se comprime la foto elegida.
  final bool processing;
  final ValueChanged<PetPhotoSource> onPick;
  final bool enabled;

  Future<void> _chooseSource(BuildContext context) async {
    final source = await showModalBottomSheet<PetPhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, PetPhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, PetPhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) onPick(source);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photo != null || photoPath != null;
    final canPick = enabled && !processing;
    return Column(
      children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: canPick ? () => _chooseSource(context) : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PetAvatar(photoPath: photoPath, bytes: photo?.bytes, size: 104),
              if (processing) const CircularProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (processing)
          Text('Comprimiendo foto…',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted))
        else
          TextButton.icon(
            onPressed: canPick ? () => _chooseSource(context) : null,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(hasPhoto ? 'Cambiar foto' : 'Agregar foto'),
          ),
      ],
    );
  }
}
