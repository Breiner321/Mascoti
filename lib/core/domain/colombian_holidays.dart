import 'package:flutter/foundation.dart';

/// Un festivo de Colombia ('YYYY-MM-DD').
@immutable
class Holiday {
  const Holiday(this.fecha, this.nombre);

  final String fecha;
  final String nombre;

  @override
  bool operator ==(Object other) =>
      other is Holiday && other.fecha == fecha && other.nombre == nombre;

  @override
  int get hashCode => Object.hash(fecha, nombre);

  @override
  String toString() => '$fecha $nombre';
}

/// Festivos de Colombia calculados en la app, sin API externa (Cambio 2):
/// la agenda de la clínica los sugiere para bloquearlos con un toque.
///
/// - Fechas fijas: 1 ene, 1 may, 20 jul, 7 ago, 8 dic, 25 dic.
/// - Ley Emiliani (Ley 51 de 1983): se pasan al lunes siguiente si no caen
///   en lunes: Reyes, San José, San Pedro y San Pablo, Asunción, Día de la
///   Raza, Todos los Santos e Independencia de Cartagena.
/// - Según la Pascua (algoritmo de Gauss/Butcher): Jueves y Viernes Santo, y
///   Ascensión, Corpus Christi y Sagrado Corazón (trasladados a lunes).
abstract final class ColombianHolidays {
  static List<Holiday> forYear(int year) {
    final easter = _easter(year);
    final list = <(DateTime, String)>[
      (DateTime.utc(year, 1, 1), 'Año Nuevo'),
      (_nextMonday(DateTime.utc(year, 1, 6)), 'Día de los Reyes Magos'),
      (_nextMonday(DateTime.utc(year, 3, 19)), 'Día de San José'),
      (easter.subtract(const Duration(days: 3)), 'Jueves Santo'),
      (easter.subtract(const Duration(days: 2)), 'Viernes Santo'),
      (DateTime.utc(year, 5, 1), 'Día del Trabajo'),
      (easter.add(const Duration(days: 43)), 'Ascensión del Señor'),
      (easter.add(const Duration(days: 64)), 'Corpus Christi'),
      (easter.add(const Duration(days: 71)), 'Sagrado Corazón de Jesús'),
      (_nextMonday(DateTime.utc(year, 6, 29)), 'San Pedro y San Pablo'),
      (DateTime.utc(year, 7, 20), 'Día de la Independencia'),
      (DateTime.utc(year, 8, 7), 'Batalla de Boyacá'),
      (_nextMonday(DateTime.utc(year, 8, 15)), 'Asunción de la Virgen'),
      (_nextMonday(DateTime.utc(year, 10, 12)), 'Día de la Raza'),
      (_nextMonday(DateTime.utc(year, 11, 1)), 'Todos los Santos'),
      (_nextMonday(DateTime.utc(year, 11, 11)), 'Independencia de Cartagena'),
      (DateTime.utc(year, 12, 8), 'Inmaculada Concepción'),
      (DateTime.utc(year, 12, 25), 'Navidad'),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (d, name) in list) Holiday(_key(d), name)];
  }

  /// Festivos entre [from] y [to] ('YYYY-MM-DD', inclusive).
  static List<Holiday> between(String from, String to) {
    final first = int.parse(from.substring(0, 4));
    final last = int.parse(to.substring(0, 4));
    return [
      for (var y = first; y <= last; y++)
        for (final h in forYear(y))
          if (h.fecha.compareTo(from) >= 0 && h.fecha.compareTo(to) <= 0) h,
    ];
  }

  /// Domingo de Pascua (calendario gregoriano, algoritmo anónimo de Butcher).
  static DateTime _easter(int y) {
    final a = y % 19;
    final b = y ~/ 100;
    final c = y % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = (h + l - 7 * m + 114) % 31 + 1;
    return DateTime.utc(y, month, day);
  }

  static DateTime _nextMonday(DateTime d) =>
      d.add(Duration(days: (DateTime.monday - d.weekday) % 7));

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
