import 'package:flutter/material.dart';

import '../../../core/domain/opening_hours.dart';
import '../../../core/domain/weekly_schedule.dart';
import '../../../core/format/time_format.dart';
import '../../../core/theme/app_theme.dart';

/// Horario semanal de la clínica (Cambio 2): por cada día, abierto o
/// cerrado, apertura, cierre y descanso opcional.
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

  Future<String?> _pick(BuildContext context, String current, String help) async {
    final m = OpeningHours.minutesOf(current);
    final picked = await TimeFormat.pick(
      context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: help,
    );
    if (picked == null) return null;
    return OpeningHours.formatMinutes(picked.hour * 60 + picked.minute);
  }

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
          onChanged: (h) => onChanged(schedule.withDay(day, h)),
          pick: (current, help) => _pick(context, current, help),
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
    required this.onChanged,
    required this.pick,
  });

  final Weekday day;
  final DayHours hours;
  final String? error;
  final bool enabled;
  final ValueChanged<DayHours> onChanged;
  final Future<String?> Function(String current, String help) pick;

  Future<void> _edit(String current, String help, DayHours Function(String) apply) async {
    final value = await pick(current, help);
    if (value != null) onChanged(apply(value));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget time(String label, String value, DayHours Function(String) apply) => ActionChip(
          label: Text('$label ${TimeFormat.hour(value)}'),
          onPressed: enabled ? () => _edit(value, '$label · ${day.label}', apply) : null,
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
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                time('Abre', hours.apertura, (v) => hours.copyWith(apertura: v)),
                time('Cierra', hours.cierre, (v) => hours.copyWith(cierre: v)),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
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
          const Divider(color: AppColors.border),
        ],
      ),
    );
  }
}
