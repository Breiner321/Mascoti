import 'package:intl/intl.dart';

import '../../../../core/format/bogota_time.dart';
import '../../../../core/format/time_format.dart';

final _thousands = NumberFormat('#,##0', 'es_CO');

/// 45000 → "$ 45.000".
String formatCop(double value) => '\$ ${_thousands.format(value.round())}';

const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const _weekdays = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];

String monthName(int month) => _months[month - 1];

/// "Martes 28 de octubre de 2026" para el instante [inicio], en hora de
/// Bogotá (aunque el teléfono esté en otra zona).
String formatAppointmentDay(DateTime inicio) {
  final w = BogotaTime.wallClock(inicio);
  final weekday = _weekdays[w.weekday - 1];
  return '${weekday[0].toUpperCase()}${weekday.substring(1)} '
      '${w.day} de ${_months[w.month - 1]} de ${w.year}';
}

/// "28 oct · 9:30 a. m." (tarjetas y listas).
String formatAppointmentShort(DateTime inicio, String hora) {
  final w = BogotaTime.wallClock(inicio);
  return '${w.day} ${_months[w.month - 1].substring(0, 3)} · ${TimeFormat.hour(hora)}';
}
