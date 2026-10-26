import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import 'clinic_requests_providers.dart';

/// Foto circular de la mascota de una cita; huella mientras carga o si no
/// tiene foto.
class AppointmentPetAvatar extends ConsumerWidget {
  const AppointmentPetAvatar({super.key, required this.photoPath, this.size = 52});

  final String? photoPath;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = photoPath;
    final url = path == null ? null : ref.watch(clinicPetPhotoUrlProvider(path)).value;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryContainer,
        image: url == null ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: url == null ? Icon(Icons.pets, color: AppColors.primary, size: size * 0.5) : null,
    );
  }
}
