import 'package:flutter/material.dart';

/// Horas para mostrar al usuario en formato de 12 horas con a. m./p. m.
///
/// En Firestore las horas se siguen guardando como `HH:mm` (24 h): las
/// reglas, los ids de las franjas (`2026-10-15_09:30`) y las consultas
/// dependen de ese formato. Solo cambia lo que se ve en pantalla.
abstract final class TimeFormat {
  /// `'13:50'` → `'1:50 p. m.'`, `'00:15'` → `'12:15 a. m.'`.
  /// Si el texto no es una hora válida, se devuelve tal cual.
  static String hour(String hhmm) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (match == null) return hhmm;
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    if (h > 23 || m > 59) return hhmm;
    return ofTime(TimeOfDay(hour: h, minute: m));
  }

  /// `TimeOfDay(hour: 9, minute: 5)` → `'9:05 a. m.'`.
  static String ofTime(TimeOfDay time) {
    final h12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final suffix = time.period == DayPeriod.am ? 'a. m.' : 'p. m.';
    return '$h12:${time.minute.toString().padLeft(2, '0')} $suffix';
  }

  /// Rango de horario: `'08:00', '18:00'` → `'8:00 a. m. – 6:00 p. m.'`.
  static String range(String from, String to) => '${hour(from)} – ${hour(to)}';

  /// `showTimePicker` en modo AM/PM, aunque el idioma del teléfono use 24 h.
  static Future<TimeOfDay?> pick(
    BuildContext context, {
    required TimeOfDay initialTime,
    String? helpText,
  }) =>
      showTimePicker(
        context: context,
        initialTime: initialTime,
        helpText: helpText,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        ),
      );
}
