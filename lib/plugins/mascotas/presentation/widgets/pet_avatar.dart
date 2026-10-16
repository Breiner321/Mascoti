import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../pets_providers.dart';

/// Foto circular de la mascota. Muestra [bytes] (foto recién elegida) o la
/// foto guardada en [photoPath]; mientras carga o si falla, una huella.
class PetAvatar extends ConsumerWidget {
  const PetAvatar({super.key, this.photoPath, this.bytes, this.size = 64});

  /// Ruta en Storage; se convierte en un enlace temporal para mostrarla.
  final String? photoPath;
  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = photoPath;
    final ImageProvider? image = switch ((bytes, path)) {
      (final Uint8List b, _) => MemoryImage(b),
      (_, final String p) => switch (ref.watch(petPhotoUrlProvider(p)).value) {
          final String url => NetworkImage(url),
          null => null,
        },
      _ => null,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryContainer,
        border: Border.all(color: AppColors.primary, width: 2),
        image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: image == null
          ? Icon(Icons.pets, color: AppColors.primary, size: size * 0.47)
          : null,
    );
  }
}
