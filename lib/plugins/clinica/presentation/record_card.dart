import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/medical_record.dart';
import '../../../core/format/time_format.dart';
import '../../../core/theme/app_theme.dart';

/// Consulta del historial en el perfil del paciente. Indica si la clínica
/// todavía puede corregirla (24 h) o si ya es de solo lectura.
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.record,
    required this.ownClinicId,
    required this.now,
    required this.onTap,
  });

  final MedicalRecord record;
  final String ownClinicId;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editable = record.clinicId == ownClinicId && record.isEditable(now);
    final createdAt = record.createdAt;
    final editableUntil = createdAt?.add(MedicalRecordLimits.editWindow);

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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat("d 'de' MMMM 'de' y", 'es').format(record.fecha),
                      style: theme.textTheme.labelLarge?.copyWith(color: AppColors.primary),
                    ),
                  ),
                  Icon(
                    editable ? Icons.edit_outlined : Icons.lock_outline,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              if (record.clinicNombre.isNotEmpty)
                Text(
                  record.clinicNombre,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              const SizedBox(height: 8),
              Text(
                record.diagnostico,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (record.tratamiento.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  record.tratamiento,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (record.vacunas.isNotEmpty || record.adjuntos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (record.vacunas.isNotEmpty)
                      _Info(
                        icon: Icons.vaccines_outlined,
                        text: record.vacunas.length == 1
                            ? '1 vacuna'
                            : '${record.vacunas.length} vacunas',
                      ),
                    if (record.adjuntos.isNotEmpty)
                      _Info(
                        icon: Icons.attach_file,
                        text: record.adjuntos.length == 1
                            ? '1 adjunto'
                            : '${record.adjuntos.length} adjuntos',
                      ),
                  ],
                ),
              ],
              if (editable && editableUntil != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Puedes corregirla hasta el '
                  '${DateFormat("d 'de' MMMM", 'es').format(editableUntil)} a las '
                  '${TimeFormat.ofTime(TimeOfDay.fromDateTime(editableUntil))}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
