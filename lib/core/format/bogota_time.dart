/// Fechas en hora de Colombia (America/Bogota): UTC−5 todo el año, sin
/// horario de verano. Las citas y las franjas se calculan siempre en esta
/// zona, aunque el teléfono esté en otra. Igual a
/// `supabase/functions/_shared/hora_bogota.ts`.
abstract final class BogotaTime {
  static const offset = Duration(hours: -5);

  static final _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  /// Instante (en UTC) de la hora [hour]:[minute] del día dado en Bogotá.
  static DateTime at(int year, int month, int day, [int hour = 0, int minute = 0]) =>
      DateTime.utc(year, month, day, hour, minute).subtract(offset);

  /// Instante de [fecha] 'YYYY-MM-DD' y [hora] 'HH:mm' en Bogotá, o null si
  /// el formato no sirve o la fecha no existe.
  static DateTime? tryParse(String fecha, String hora) {
    final d = _date.firstMatch(fecha);
    final t = _time.firstMatch(hora);
    if (d == null || t == null) return null;
    final instant = at(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!),
        int.parse(t[1]!), int.parse(t[2]!));
    return dateKey(instant) == fecha ? instant : null;
  }

  /// Hora de pared en Bogotá de [instant]: un DateTime UTC cuyos campos
  /// (año, mes, día, hora) son los de Bogotá. Úsalo solo para mostrar o
  /// comparar fechas, no como instante.
  static DateTime wallClock(DateTime instant) => instant.toUtc().add(offset);

  /// 'YYYY-MM-DD' del día en Bogotá al que pertenece [instant].
  static String dateKey(DateTime instant) {
    final w = wallClock(instant);
    return '${w.year.toString().padLeft(4, '0')}-'
        '${w.month.toString().padLeft(2, '0')}-'
        '${w.day.toString().padLeft(2, '0')}';
  }

  /// Inicio (00:00 en Bogotá) del día de [instant].
  static DateTime startOfDay(DateTime instant) {
    final w = wallClock(instant);
    return at(w.year, w.month, w.day);
  }

  /// Inicio del día del calendario [day] (sus campos año/mes/día, p. ej. lo
  /// que devuelve un selector de fechas), en Bogotá.
  static DateTime startOfCalendarDay(DateTime day) => at(day.year, day.month, day.day);
}
