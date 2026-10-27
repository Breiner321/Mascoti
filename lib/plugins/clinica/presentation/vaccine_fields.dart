import 'package:flutter/material.dart';

import '../../../core/domain/medical_record.dart';
import '../../../core/theme/app_theme.dart';
import 'date_form_field.dart';
import 'medical_record_validators.dart';

/// Vacuna que se está escribiendo en el formulario de consulta.
class VaccineDraft {
  VaccineDraft({String nombre = '', String lote = '', this.fechaAplicacion, this.fechaProximaDosis})
      : nombre = TextEditingController(text: nombre),
        lote = TextEditingController(text: lote);

  factory VaccineDraft.from(Vaccine v) => VaccineDraft(
        nombre: v.nombre,
        lote: v.lote,
        fechaAplicacion: v.fechaAplicacion,
        fechaProximaDosis: v.fechaProximaDosis,
      );

  /// Identifica la fila aunque cambie de posición al quitar otra.
  final Key key = UniqueKey();
  final TextEditingController nombre;
  final TextEditingController lote;
  DateTime? fechaAplicacion;
  DateTime? fechaProximaDosis;

  Vaccine toVaccine() => Vaccine(
        nombre: nombre.text.trim(),
        lote: lote.text.trim(),
        fechaAplicacion: fechaAplicacion!,
        fechaProximaDosis: fechaProximaDosis,
      );

  void dispose() {
    nombre.dispose();
    lote.dispose();
  }
}

/// Fila de una vacuna aplicada: nombre, lote, fecha de aplicación y fecha de
/// la próxima dosis (opcional, la usa RF-13 para el recordatorio).
class VaccineFields extends StatefulWidget {
  const VaccineFields({
    super.key,
    required this.index,
    required this.draft,
    required this.now,
    required this.readOnly,
    required this.onRemove,
  });

  final int index;
  final VaccineDraft draft;
  final DateTime now;
  final bool readOnly;
  final VoidCallback onRemove;

  @override
  State<VaccineFields> createState() => _VaccineFieldsState();
}

class _VaccineFieldsState extends State<VaccineFields> {
  final _nextDoseKey = GlobalKey<FormFieldState<DateTime>>();

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final readOnly = widget.readOnly;
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.vaccines_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Vacuna ${widget.index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (!readOnly)
                IconButton(
                  tooltip: 'Quitar vacuna',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onRemove,
                ),
            ],
          ),
          if (readOnly) const SizedBox(height: 8),
          TextFormField(
            controller: draft.nombre,
            enabled: !readOnly,
            maxLength: MedicalRecordLimits.maxVacunaNombre,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre de la vacuna', counterText: ''),
            validator: MedicalRecordValidators.vacunaNombre,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.lote,
            enabled: !readOnly,
            maxLength: MedicalRecordLimits.maxLote,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Lote', counterText: ''),
            validator: MedicalRecordValidators.lote,
          ),
          const SizedBox(height: 12),
          DateFormField(
            label: 'Fecha de aplicación',
            value: draft.fechaAplicacion,
            enabled: !readOnly,
            firstDate: DateTime(2000),
            lastDate: today,
            onChanged: (d) {
              setState(() => draft.fechaAplicacion = d);
              // La próxima dosis depende de esta fecha: se vuelve a validar.
              if (draft.fechaProximaDosis != null) _nextDoseKey.currentState?.validate();
            },
            validator: (d) => MedicalRecordValidators.fechaAplicacion(d, widget.now),
          ),
          const SizedBox(height: 12),
          DateFormField(
            key: _nextDoseKey,
            label: 'Próxima dosis (opcional)',
            value: draft.fechaProximaDosis,
            enabled: !readOnly,
            clearable: true,
            firstDate: DateTime(2000),
            lastDate: DateTime(today.year + 10, 12, 31),
            onChanged: (d) => setState(() => draft.fechaProximaDosis = d),
            validator: (d) => MedicalRecordValidators.fechaProximaDosis(d, draft.fechaAplicacion),
          ),
        ],
      ),
    );
  }
}
