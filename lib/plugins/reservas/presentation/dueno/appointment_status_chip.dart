import 'package:flutter/material.dart';

import '../../../../core/domain/appointment.dart';
import '../../../../core/theme/app_theme.dart';

/// Chip con el estado de la cita y su color.
class AppointmentStatusChip extends StatelessWidget {
  const AppointmentStatusChip({super.key, required this.status});

  final AppointmentStatus status;

  /// (texto, fondo) de cada estado.
  static (Color, Color) colorsOf(AppointmentStatus status) => switch (status) {
        AppointmentStatus.pendiente => (AppColors.slotBlocked, AppColors.slotBlockedContainer),
        AppointmentStatus.confirmada => (AppColors.success, AppColors.slotAvailableContainer),
        AppointmentStatus.completada => (AppColors.primary, AppColors.primaryContainer),
        AppointmentStatus.rechazada ||
        AppointmentStatus.noAsistio =>
          (AppColors.sos, AppColors.sosContainer),
        AppointmentStatus.cancelada ||
        AppointmentStatus.expirada =>
          (AppColors.slotLocked, AppColors.slotLockedContainer),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colorsOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}
