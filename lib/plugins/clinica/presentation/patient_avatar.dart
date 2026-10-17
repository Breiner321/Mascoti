import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'clinic_providers.dart';

/// Foto circular de un paciente (bucket `mascotas`); mientras carga, si no
/// tiene foto o si falla, una huella.
class PatientAvatar extends ConsumerWidget {
  const PatientAvatar({super.key, this.photoPath, this.size = 56});

  final String? photoPath;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = photoPath;
    final url = path == null ? null : ref.watch(patientPhotoUrlProvider(path)).value;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryContainer,
        border: Border.all(color: AppColors.primary, width: 2),
        image: url == null ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: url == null ? Icon(Icons.pets, color: AppColors.primary, size: size * 0.47) : null,
    );
  }
}
