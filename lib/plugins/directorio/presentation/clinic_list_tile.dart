import 'package:flutter/material.dart';

import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/clinic_schedule.dart';
import '../domain/directory_filters.dart';

/// Clínica en la lista bajo el mapa (mockup VISTA CLIENTE – Mapa):
/// nombre, "Veterinaria · Abierto", distancia y botón "Agendar".
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
    final open = openLabel(clinic.horarioBase, DateTime.now());
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
          subtitle: Text(subtitle,
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          trailing: FilledButton(
            onPressed: onSchedule,
            // El tema usa botones de ancho completo; en la fila va compacto.
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('Agendar'),
          ),
        ),
      ),
    );
  }
}
