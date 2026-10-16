import 'package:flutter/foundation.dart';

/// Horario base de la clínica (`clinics.horarioBase`, RF-06): a partir de él
/// se generan las franjas del día. Horas en formato 24 h `HH:mm`.
@immutable
class OpeningHours {
  const OpeningHours({
    required this.apertura,
    required this.cierre,
    required this.duracionSlotMin,
  });

  factory OpeningHours.fromMap(Map<String, dynamic> map) => OpeningHours(
        apertura: map['apertura'] as String? ?? '08:00',
        cierre: map['cierre'] as String? ?? '18:00',
        duracionSlotMin: (map['duracionSlotMin'] as num?)?.toInt() ?? 30,
      );

  /// Valor por defecto del mockup: 08:00–18:00 en bloques de 30 minutos.
  static const standard =
      OpeningHours(apertura: '08:00', cierre: '18:00', duracionSlotMin: 30);

  static final RegExp _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  final String apertura;
  final String cierre;
  final int duracionSlotMin;

  Map<String, dynamic> toMap() => {
        'apertura': apertura,
        'cierre': cierre,
        'duracionSlotMin': duracionSlotMin,
      };

  OpeningHours copyWith({String? apertura, String? cierre, int? duracionSlotMin}) =>
      OpeningHours(
        apertura: apertura ?? this.apertura,
        cierre: cierre ?? this.cierre,
        duracionSlotMin: duracionSlotMin ?? this.duracionSlotMin,
      );

  /// Formato correcto, apertura antes del cierre y duración entre 5 y 480 min.
  bool get isValid =>
      _time.hasMatch(apertura) &&
      _time.hasMatch(cierre) &&
      minutesOf(apertura) < minutesOf(cierre) &&
      duracionSlotMin >= 5 &&
      duracionSlotMin <= 480;

  /// Horas de inicio de las franjas del día: ['08:00', '08:30', …]. La última
  /// franja debe terminar a más tardar a la hora de cierre.
  List<String> slotTimes() {
    if (!isValid) return const [];
    final end = minutesOf(cierre);
    return [
      for (var m = minutesOf(apertura); m + duracionSlotMin <= end; m += duracionSlotMin)
        formatMinutes(m),
    ];
  }

  /// '08:30' → 510.
  static int minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// 510 → '08:30'.
  static String formatMinutes(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is OpeningHours &&
      other.apertura == apertura &&
      other.cierre == cierre &&
      other.duracionSlotMin == duracionSlotMin;

  @override
  int get hashCode => Object.hash(apertura, cierre, duracionSlotMin);
}
