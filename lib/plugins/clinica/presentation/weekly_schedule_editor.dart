import 'package:flutter/material.dart';

import '../../../core/domain/weekly_schedule.dart';
import '../../../core/theme/app_theme.dart';
import 'clock_time_input.dart';

/// Horario semanal de la clínica (Cambio 2): por cada día, abierto o
/// cerrado, apertura, cierre y descanso opcional. Las horas se escriben con
/// [ClockTimeInput] (hora, minutos y a. m. / p. m.), sin reloj.
class WeeklyScheduleEditor extends StatelessWidget {
  const WeeklyScheduleEditor({
    super.key,
    required this.schedule,
    required this.slotMinutes,
    required this.onChanged,
    this.enabled = true,
  });

  final WeeklySchedule schedule;
  final int slotMinutes;
  final ValueChanged<WeeklySchedule> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in Weekday.values) _DayRow(
          day: day,
          hours: schedule[day],
          error: schedule[day].validate(slotMinutes),
          enabled: enabled,
          slotMinutes: slotMinutes,
          onChanged: (h) => onChanged(schedule.withDay(day, h)),
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.hours,
    required this.error,
    required this.enabled,
    required this.slotMinutes,
    required this.onChanged,
  });

  final Weekday day;
  final DayHours hours;
  final String? error;
  final bool enabled;
  final int slotMinutes;
  final ValueChanged<DayHours> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget time(String label, String value, DayHours Function(String) apply) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ClockTimeInput(
            key: ValueKey('${day.key}-$label'),
            label: label,
            semanticLabel: '$label el ${day.label}',
            value: value,
            stepMinutes: slotMinutes,
            enabled: enabled,
            onChanged: (v) => onChanged(apply(v)),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(day.label, style: textTheme.titleSmall),
            subtitle: Text(hours.abierto ? 'Abierto' : 'Cerrado'),
            value: hours.abierto,
            onChanged: enabled ? (v) => onChanged(hours.copyWith(abierto: v)) : null,
          ),
          if (hours.abierto) ...[
            time('Abre', hours.apertura, (v) => hours.copyWith(apertura: v)),
            time('Cierra', hours.cierre, (v) => hours.copyWith(cierre: v)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilterChip(
                  label: const Text('Descanso'),
                  selected: hours.hasBreak,
                  onSelected: enabled
                      ? (on) => onChanged(on
                          ? hours.copyWith(descansoInicio: '12:00', descansoFin: '14:00')
                          : hours.copyWith(clearBreak: true))
                      : null,
                ),
                if (hours.hasBreak) ...[
                  time('Desde', hours.descansoInicio!, (v) => hours.copyWith(descansoInicio: v)),
                  time('Hasta', hours.descansoFin!, (v) => hours.copyWith(descansoFin: v)),
                ],
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        error!,
                        style: textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          Divider(color: AppColors.border),
        ],
      ),
    );
  }
}
