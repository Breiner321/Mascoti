import '../../../core/domain/opening_hours.dart';

/// Si la clínica está abierta en [now] según su horario base (RF-04).
/// null = no configuró horario.
bool? isOpenAt(OpeningHours? hours, DateTime now) {
  if (hours == null || !hours.isValid) return null;
  final minute = now.hour * 60 + now.minute;
  return minute >= OpeningHours.minutesOf(hours.apertura) &&
      minute < OpeningHours.minutesOf(hours.cierre);
}

/// "Abierto" / "Cerrado", o null si no hay horario.
String? openLabel(OpeningHours? hours, DateTime now) =>
    switch (isOpenAt(hours, now)) {
      true => 'Abierto',
      false => 'Cerrado',
      null => null,
    };
