import '../format/bogota_time.dart';
import 'opening_hours.dart';
import 'schedule_exception.dart';
import 'weekly_schedule.dart';

/// Estado de una franja en la agenda de la clínica (Cambio 2).
enum CellStatus {
  /// Dentro del horario y sin cita: se puede reservar.
  libre,

  /// Apartada por una cita (pendiente o confirmada).
  ocupada,

  /// Bloqueada por una excepción de la clínica (o una franja antigua
  /// "No disponible").
  bloqueada,
}

/// Una franja del día en la agenda de la clínica.
typedef DayCell = ({String hora, CellStatus status, ScheduleException? exception});

/// "¿Qué franjas están libres el día X para el servicio Y?" (Cambio 2).
///
/// Funciones puras, en hora de Colombia. Son la ÚNICA lógica de
/// disponibilidad de la app y tienen su gemela en
/// `supabase/functions/_shared/disponibilidad.ts`, que la Edge Function
/// `citas` usa para validar. Ambas pasan los mismos casos de
/// `test/fixtures/disponibilidad.json`.
///
/// Modelo: el día se divide en franjas de `reservas.duracionSlotMin`
/// alineadas a las 00:00. Un servicio ocupa las franjas consecutivas que
/// necesite (60 min = 2 franjas de 30). Una franja está ocupada si su
/// documento `slots/{fecha}_{hora}` tiene un estado de [busyStates].
abstract final class Availability {
  /// Estados de `slots` que ocupan la franja. 'disponible' (o sin documento)
  /// es libre; 'no_disponible' es una franja antigua bloqueada a mano.
  static const busyStates = {'reservado_temporal', 'ocupado', 'no_disponible'};

  static const _dayMinutes = 24 * 60;

  /// Tramos de atención de [fecha] en minutos: horario semanal + aperturas
  /// extra − bloqueos. Ordenados y sin solaparse.
  static List<(int, int)> openIntervals({
    required String fecha,
    required WeeklySchedule schedule,
    Iterable<ScheduleException> exceptions = const [],
  }) {
    final applying = [for (final e in exceptions) if (e.covers(fecha)) e];
    var intervals = <(int, int)>[
      ...schedule.forDate(fecha).intervals,
      for (final e in applying)
        if (e.tipo == ExceptionType.apertura && !e.isFullDay) e.minutes,
    ];
    intervals = _merge(intervals);
    for (final e in applying) {
      if (e.tipo == ExceptionType.bloqueo) intervals = _subtract(intervals, e.minutes);
    }
    return intervals;
  }

  /// Franjas ('HH:mm') que ocupa un servicio de [durationMin] que empieza a
  /// [hora], con franjas de [slotMinutes]. Son los ids de `slots` que aparta
  /// la reserva.
  static List<String> cellsFor(String hora, int durationMin, int slotMinutes) {
    final start = OpeningHours.minutesOf(hora);
    return [
      for (var i = 0; i < _cellCount(durationMin, slotMinutes); i++)
        OpeningHours.formatMinutes(start + i * slotMinutes),
    ];
  }

  /// Horas de inicio ('HH:mm', en orden) en las que se puede reservar un
  /// servicio de [durationMin] el día [fecha]:
  /// - todas sus franjas dentro del horario (no cruza el descanso ni el
  ///   cierre) y sin bloqueos;
  /// - ninguna franja ocupada ([slotStates]: hora → estado de `slots`);
  /// - empieza después de `now + anticipacionMinMin` y la fecha no pasa de
  ///   hoy + `anticipacionMaxDias` (días en hora de Colombia).
  static List<String> startTimes({
    required String fecha,
    required int durationMin,
    required WeeklySchedule schedule,
    required BookingSettings settings,
    required DateTime now,
    Iterable<ScheduleException> exceptions = const [],
    Map<String, String> slotStates = const {},
  }) {
    final lastDate = BogotaTime.dateKey(
      BogotaTime.startOfDay(now).add(Duration(days: settings.anticipacionMaxDias)),
    );
    if (fecha.compareTo(lastDate) > 0) return const [];
    final earliest = now.add(Duration(minutes: settings.anticipacionMinMin));

    final step = settings.duracionSlotMin;
    final cells = _cellCount(durationMin, step);
    final open = openIntervals(fecha: fecha, schedule: schedule, exceptions: exceptions);
    final result = <String>[];
    for (var start = 0; start + cells * step <= _dayMinutes; start += step) {
      final hora = OpeningHours.formatMinutes(start);
      final fits = [
        for (var i = 0; i < cells; i++) start + i * step,
      ].every((c) => _inside(open, c, c + step) && !_busy(slotStates, c));
      if (!fits) continue;
      final instant = BogotaTime.tryParse(fecha, hora);
      if (instant == null || !instant.isAfter(now) || instant.isBefore(earliest)) continue;
      result.add(hora);
    }
    return result;
  }

  /// ¿Una cita a [hora] de [durationMin] cabe en el horario y las
  /// excepciones? Sin mirar ocupación ni anticipación: sirve para avisar a la
  /// clínica qué citas quedan por fuera de un horario nuevo.
  static bool fitsSchedule({
    required String fecha,
    required String hora,
    required int durationMin,
    required WeeklySchedule schedule,
    required int slotMinutes,
    Iterable<ScheduleException> exceptions = const [],
  }) {
    final open = openIntervals(fecha: fecha, schedule: schedule, exceptions: exceptions);
    final start = OpeningHours.minutesOf(hora);
    final end = start + _cellCount(durationMin, slotMinutes) * slotMinutes;
    return _inside(open, start, end);
  }

  /// Franjas del día para la agenda de la clínica: las del horario (con
  /// aperturas extra) y las bloqueadas, con su estado.
  static List<DayCell> dayCells({
    required String fecha,
    required WeeklySchedule schedule,
    required int slotMinutes,
    Iterable<ScheduleException> exceptions = const [],
    Map<String, String> slotStates = const {},
  }) {
    final applying = [for (final e in exceptions) if (e.covers(fecha)) e];
    final scheduled = _merge([
      ...schedule.forDate(fecha).intervals,
      for (final e in applying)
        if (e.tipo == ExceptionType.apertura && !e.isFullDay) e.minutes,
    ]);
    final result = <DayCell>[];
    for (var start = 0; start + slotMinutes <= _dayMinutes; start += slotMinutes) {
      final end = start + slotMinutes;
      final hora = OpeningHours.formatMinutes(start);
      final state = slotStates[hora];
      final inSchedule = _inside(scheduled, start, end);
      // Una franja antigua "No disponible" fuera del horario se muestra igual.
      if (!inSchedule && state == null) continue;
      ScheduleException? block;
      for (final e in applying) {
        if (e.tipo != ExceptionType.bloqueo) continue;
        final (b0, b1) = e.minutes;
        if (start < b1 && b0 < end) {
          block = e;
          break;
        }
      }
      final status = state == 'reservado_temporal' || state == 'ocupado'
          ? CellStatus.ocupada
          : block != null || state == 'no_disponible' || !inSchedule
              ? CellStatus.bloqueada
              : CellStatus.libre;
      result.add((hora: hora, status: status, exception: block));
    }
    return result;
  }

  static int _cellCount(int durationMin, int slotMinutes) =>
      durationMin <= 0 ? 1 : (durationMin + slotMinutes - 1) ~/ slotMinutes;

  static bool _busy(Map<String, String> slotStates, int minute) =>
      busyStates.contains(slotStates[OpeningHours.formatMinutes(minute)]);

  static bool _inside(List<(int, int)> intervals, int start, int end) =>
      intervals.any((i) => i.$1 <= start && end <= i.$2);

  static List<(int, int)> _merge(List<(int, int)> intervals) {
    final sorted = [for (final i in intervals) if (i.$1 < i.$2) i]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final i in sorted) {
      if (merged.isNotEmpty && i.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, i.$2 > last.$2 ? i.$2 : last.$2));
      } else {
        merged.add(i);
      }
    }
    return merged;
  }

  static List<(int, int)> _subtract(List<(int, int)> intervals, (int, int) cut) {
    final (c0, c1) = cut;
    return [
      for (final (a, b) in intervals) ...[
        if (c1 <= a || b <= c0) (a, b) else ...[
          if (a < c0) (a, c0),
          if (c1 < b) (c1, b),
        ],
      ],
    ];
  }
}
