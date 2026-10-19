import 'package:flutter/material.dart';

import '../../../../core/domain/medical_record.dart';
import '../../../../core/theme/app_theme.dart';
import 'record_attachment_tile.dart';

/// Una consulta en la línea de tiempo: punto y línea vertical a la izquierda
/// y una tarjeta que se expande para ver tratamiento, vacunas y adjuntos.
class RecordTimelineTile extends StatelessWidget {
  const RecordTimelineTile({
    super.key,
    required this.record,
    required this.isFirst,
    required this.isLast,
  });

  final MedicalRecord record;
  final bool isFirst;
  final bool isLast;

  static const _dotTop = 22.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dates = MaterialLocalizations.of(context);
    return Stack(
      children: [
        // Línea vertical: del punto anterior al siguiente.
        Positioned(
          left: 11,
          top: isFirst ? _dotTop : 0,
          bottom: isLast ? null : 0,
          height: isLast ? _dotTop : null,
          child: Container(width: 2, color: AppColors.primarySoft),
        ),
        Positioned(
          left: 4,
          top: _dotTop - 8,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isFirst ? AppColors.primary : AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 32, bottom: 12),
          child: Card(
            margin: EdgeInsets.zero,
            color: AppColors.surface,
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dates.formatMediumDate(record.fecha),
                    style: textTheme.labelMedium?.copyWith(color: AppColors.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.diagnostico,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.local_hospital_outlined,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        record.clinicNombre.isEmpty ? 'Clínica' : record.clinicNombre,
                        style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              children: [_RecordDetail(record: record)],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordDetail extends StatelessWidget {
  const _RecordDetail({required this.record});

  final MedicalRecord record;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dates = MaterialLocalizations.of(context);
    final muted = textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text('Diagnóstico', style: muted),
        Text(record.diagnostico, style: textTheme.bodyMedium),
        const SizedBox(height: 12),
        Text('Tratamiento', style: muted),
        Text(
          record.tratamiento.trim().isEmpty ? 'Sin tratamiento registrado' : record.tratamiento,
          style: textTheme.bodyMedium,
        ),
        if (record.vacunas.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Vacunas aplicadas', style: muted),
          const SizedBox(height: 4),
          for (final v in record.vacunas)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.vaccines_outlined, color: AppColors.primary),
              title: Text(v.nombre),
              subtitle: Text([
                'Lote ${v.lote}',
                if (v.fechaProximaDosis case final next?)
                  'Próxima dosis: ${dates.formatMediumDate(next)}',
              ].join(' · ')),
            ),
        ],
        if (record.adjuntos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Adjuntos', style: muted),
          const SizedBox(height: 8),
          for (final a in record.adjuntos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordAttachmentTile(petId: record.petId, attachment: a),
            ),
        ],
      ],
    );
  }
}
