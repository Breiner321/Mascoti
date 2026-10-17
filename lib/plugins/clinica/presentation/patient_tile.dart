import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/patient.dart';
import 'patient_avatar.dart';

/// Fila de la lista de pacientes: foto, nombre, especie y dueño.
class PatientTile extends StatelessWidget {
  const PatientTile({super.key, required this.patient, required this.onTap});

  final Patient patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pet = patient.pet;
    final theme = Theme.of(context);
    final especie = [pet.especie.label, if (pet.raza?.isNotEmpty ?? false) pet.raza!].join(' · ');
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PatientAvatar(photoPath: pet.fotoPath),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.nombre,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(especie, style: theme.textTheme.bodyMedium),
                    Text(
                      patient.duenoNombre.isEmpty
                          ? 'Dueño: sin registrar'
                          : 'Dueño: ${patient.duenoNombre}',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (pet.alergias.isNotEmpty || pet.condiciones.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Tiene alergias o condiciones',
                    child: Icon(Icons.warning_amber_rounded, color: AppColors.sos),
                  ),
                ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
