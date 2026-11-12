import '../../../core/domain/opening_hours.dart';
import '../../../core/domain/weekly_schedule.dart';
import '../../../core/format/bogota_time.dart';
import '../../../core/format/time_format.dart';

/// Si la clínica está abierta en [now] según su horario semanal (Cambio 2),
/// en hora de Colombia. null = no configuró horario.
bool? isOpenAt(WeeklySchedule? schedule, DateTime now) {
  if (schedule == null) return null;
  final wall = BogotaTime.wallClock(now);
  final minute = wall.hour * 60 + wall.minute;
  return schedule[Weekday.of(wall.weekday)]
      .intervals
      .any((i) => minute >= i.$1 && minute < i.$2);
}

/// "Abierto" / "Cerrado", o null si no hay horario.
String? openLabel(WeeklySchedule? schedule, DateTime now) =>
    switch (isOpenAt(schedule, now)) {
      true => 'Abierto',
      false => 'Cerrado',
      null => null,
    };

/// Horario de hoy: "8:00 a. m. – 6:00 p. m." (con descanso, los dos tramos)
/// o "Hoy no atiende". null si no hay horario.
String? todayHoursLabel(WeeklySchedule? schedule, DateTime now) {
  if (schedule == null) return null;
  final day = schedule[Weekday.of(BogotaTime.wallClock(now).weekday)];
  if (!day.abierto) return 'Hoy no atiende';
  return [
    for (final (a, b) in day.intervals)
      TimeFormat.range(OpeningHours.formatMinutes(a), OpeningHours.formatMinutes(b)),
  ].join(' · ');
}
