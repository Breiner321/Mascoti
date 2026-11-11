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

  /// Ícono de cada estado: el estado no depende solo del color (Cambio 3).
  static IconData iconOf(AppointmentStatus status) => switch (status) {
        AppointmentStatus.pendiente => Icons.hourglass_top,
        AppointmentStatus.confirmada => Icons.check_circle,
        AppointmentStatus.completada => Icons.task_alt,
        AppointmentStatus.rechazada => Icons.cancel,
        AppointmentStatus.noAsistio => Icons.person_off,
        AppointmentStatus.cancelada => Icons.event_busy,
        AppointmentStatus.expirada => Icons.timer_off,
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colorsOf(status);
    return Semantics(
      label: 'Estado: ${status.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconOf(status), size: 16, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                status.label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
