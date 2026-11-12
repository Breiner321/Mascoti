import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Forma del marcador (Cambio 4), en el mapa y en la leyenda. Aliado
/// Mascoti: círculo morado con huella (rojo SOS si atiende emergencias).
/// Otra veterinaria: círculo gris más pequeño con cruz médica. Se distinguen
/// por forma y tamaño, no solo por el color.
class VetMarkerIcon extends StatelessWidget {
  const VetMarkerIcon({super.key, required this.ally, this.emergency = false, this.scale = 1});

  final bool ally;
  final bool emergency;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = (ally ? 36.0 : 28.0) * scale;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ally ? (emergency ? AppColors.sos : AppColors.primary) : AppColors.textMuted,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2 * scale),
      ),
      child: Icon(
        ally ? Icons.pets : Icons.local_hospital,
        size: (ally ? 20 : 16) * scale,
        color: AppColors.surface,
      ),
    );
  }
}
