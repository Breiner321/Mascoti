import 'package:flutter/material.dart';

import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/clinic_schedule.dart';
import '../domain/directory_filters.dart';
import 'ally_badge.dart';

/// Clínica en la lista bajo el mapa (mockup VISTA CLIENTE – Mapa):
/// nombre, "Veterinaria · Abierto", distancia, "Aliado Mascoti" (Cambio 4)
/// y botón "Agendar".
class ClinicListTile extends StatelessWidget {
  const ClinicListTile({
    super.key,
    required this.nearby,
    required this.onTap,
    required this.onSchedule,
    this.selected = false,
  });

  final NearbyClinic nearby;
  final VoidCallback onTap;
  final VoidCallback onSchedule;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final clinic = nearby.clinic;
    final textTheme = Theme.of(context).textTheme;
    final open = openLabel(clinic.schedule, DateTime.now());
    final subtitle = [
      clinic.atencionEmergencias ? 'Urgencias' : 'Veterinaria',
      if (open != null) open,
      distanceLabel(nearby.distanceKm),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primaryContainer : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
          leading: Icon(
            clinic.atencionEmergencias
                ? Icons.emergency_outlined
                : Icons.local_hospital_outlined,
            color:
                clinic.atencionEmergencias ? AppColors.sos : AppColors.primary,
          ),
          title: Text(
            clinic.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle,
                  style:
                      textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: 4),
              const AllyBadge(),
            ],
          ),
          trailing: FilledButton(
            onPressed: onSchedule,
            // El tema usa botones de ancho completo; en la fila va compacto.
            style: FilledButton.styleFrom(
              // 48 dp: área táctil mínima (Cambio 3).
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('Agendar'),
          ),
        ),
      ),
    );
  }
}
