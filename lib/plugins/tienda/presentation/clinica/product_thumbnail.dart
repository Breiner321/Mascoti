import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import 'clinic_shop_providers.dart';

/// Foto cuadrada del producto. Muestra [bytes] (foto recién elegida) o la
/// foto guardada en [photoPath]; mientras carga o si falla, un ícono.
class ProductThumbnail extends ConsumerWidget {
  const ProductThumbnail({super.key, this.photoPath, this.bytes, this.size = 64, this.name});

  /// Ruta en el bucket `productos`; se convierte en un enlace temporal.
  final String? photoPath;
  final Uint8List? bytes;
  final double size;

  /// Nombre del producto para el lector de pantalla ("Foto de Collar").
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = photoPath;
    final ImageProvider? image = switch ((bytes, path)) {
      (final Uint8List b, _) => MemoryImage(b),
      (_, final String p) when p.isNotEmpty => switch (
            ref.watch(productPhotoUrlProvider(p)).value) {
          final String url => NetworkImage(url),
          null => null,
        },
      _ => null,
    };
    return Semantics(
      image: true,
      label: name == null || name!.isEmpty ? 'Foto del producto' : 'Foto de $name',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.primaryContainer,
          border: Border.all(color: AppColors.border),
          image: image == null ? null : DecorationImage(image: image, fit: BoxFit.cover),
        ),
        child: image == null
            ? Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: size * 0.45)
            : null,
      ),
    );
  }
}
