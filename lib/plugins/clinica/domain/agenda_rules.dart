import '../../../core/domain/appointment.dart';
import '../../../core/domain/availability.dart';
import '../../../core/domain/colombian_holidays.dart';
import '../../../core/domain/opening_hours.dart';
import '../../../core/domain/schedule_exception.dart';
import '../../../core/domain/weekly_schedule.dart';

/// Reglas de la agenda de la clínica (Cambio 2), sin widgets para probarlas.
abstract final class AgendaRules {
  /// Agrupa las franjas seleccionadas ('HH:mm') en rangos seguidos
  /// [desde, hasta) para bloquearlas con una excepción por rango.
  static List<(String, String)> contiguousRanges(Iterable<String> horas, int slotMinutes) {
    final sorted = horas.map(OpeningHours.minutesOf).toSet().toList()..sort();
    final ranges = <(int, int)>[];
    for (final m in sorted) {
      if (ranges.isNotEmpty && ranges.last.$2 == m) {
        ranges[ranges.length - 1] = (ranges.last.$1, m + slotMinutes);
      } else {
        ranges.add((m, m + slotMinutes));
      }
    }
    return [
      for (final (a, b) in ranges)
        // Una franja que termina a medianoche se guarda como 23:59.
        (OpeningHours.formatMinutes(a), b >= 24 * 60 ? '23:59' : OpeningHours.formatMinutes(b)),
    ];
  }

  /// ¿La clínica bloqueó todo el día [fecha]?
  static ScheduleException? fullDayBlock(Iterable<ScheduleException> exceptions, String fecha) {
    for (final e in exceptions) {
      if (e.tipo == ExceptionType.bloqueo && e.isFullDay && e.covers(fecha)) return e;
    }
    return null;
  }

  /// Festivos entre [desde] y [hasta] que caen en un día de atención y que la
  /// clínica todavía no ha bloqueado: se sugieren para bloquear con un toque.
  static List<Holiday> holidaySuggestions({
    required String desde,
    required String hasta,
    required WeeklySchedule schedule,
    required Iterable<ScheduleException> exceptions,
  }) =>
      [
        for (final h in ColombianHolidays.between(desde, hasta))
          if (schedule.forDate(h.fecha).abierto && fullDayBlock(exceptions, h.fecha) == null) h,
      ];

  /// Citas pendientes o confirmadas desde [now] que quedarían por fuera de un
  /// horario nuevo. Se avisan y se listan antes de guardar; las citas se
  /// mantienen (decisión del equipo).
  static List<Appointment> conflictsWith({
    required Iterable<Appointment> appointments,
    required WeeklySchedule schedule,
    required int slotMinutes,
    required DateTime now,
    Iterable<ScheduleException> exceptions = const [],
  }) =>
      [
        for (final a in appointments)
          if (a.estado.isActive &&
              a.inicio.isAfter(now) &&
              !Availability.fitsSchedule(
                fecha: a.fecha,
                hora: a.hora,
                durationMin: a.duracionMin ?? slotMinutes,
                schedule: schedule,
                slotMinutes: slotMinutes,
                exceptions: exceptions,
              ))
            a,
      ]..sort((a, b) => a.inicio.compareTo(b.inicio));
}
