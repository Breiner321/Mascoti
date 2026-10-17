import 'package:flutter/material.dart';

import '../../../core/domain/slot.dart';
import '../../../core/format/time_format.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/day_schedule.dart';
import 'service_validators.dart';

/// Una franja en la vista del día (RF-06). Verde = disponible, gris =
/// ocupada/reservada (solo lectura), ámbar = no disponible.
class SlotTile extends StatelessWidget {
  const SlotTile({
    super.key,
    required this.franja,
    required this.serviceName,
    required this.selected,
    required this.past,
    required this.onTap,
  });

  final Franja franja;

  /// Nombre del servicio de la franja (o de la que la cubre); null si no aplica.
  final String? serviceName;
  final bool selected;

  /// Ya empezó: se ve atenuada y no se edita.
  final bool past;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    final slot = franja.slot;

    final (Color background, Color accent, String label, IconData? icon) =
        switch (franja.kind) {
      FranjaKind.available => (
          AppColors.slotAvailableContainer,
          AppColors.slotAvailable,
          [
            serviceName ?? 'Servicio inactivo',
            if (slot?.precio != null) formatCop(slot!.precio!),
          ].join(' · '),
          Icons.check_circle_outline,
        ),
      FranjaKind.unavailable => (
          AppColors.slotBlockedContainer,
          AppColors.slotBlocked,
          'No disponible',
          Icons.block,
        ),
      FranjaKind.locked => (
          AppColors.slotLockedContainer,
          AppColors.slotLocked,
          slot!.estado == SlotStatus.ocupado ? 'Ocupado' : 'Reservado',
          Icons.lock_outline,
        ),
      FranjaKind.covered => (
          AppColors.slotCovered,
          AppColors.slotAvailable,
          '↳ ${serviceName ?? 'Servicio'} ${franja.coveredBy}',
          null,
        ),
      FranjaKind.empty => (
          AppColors.surface,
          AppColors.textMuted,
          'Sin configurar',
          null,
        ),
    };

    final borderColor = franja.conflict
        ? error
        : selected
            ? AppColors.primary
            : AppColors.border;

    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor,
            width: selected || franja.conflict ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    // "10:20 a. m." es más largo que "10:20": se reduce para
                    // caber en la grilla de 3 columnas sin desbordar.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          TimeFormat.hour(franja.hora),
                          maxLines: 1,
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (franja.edited)
                      const Icon(Icons.edit, size: 14, color: AppColors.primary),
                    if (selected)
                      const Icon(Icons.check_box, size: 18, color: AppColors.primary)
                    else if (franja.conflict)
                      Icon(Icons.error_outline, size: 18, color: error)
                    else if (icon != null)
                      Icon(icon, size: 18, color: accent),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
