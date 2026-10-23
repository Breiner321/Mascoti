import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/format/bogota_time.dart';

void main() {
  test('fecha y hora en Bogotá → instante UTC (UTC−5)', () {
    expect(BogotaTime.at(2026, 11, 5, 9, 30), DateTime.utc(2026, 11, 5, 14, 30));
    // 21:00 en Bogotá ya es el día siguiente en UTC.
    expect(BogotaTime.tryParse('2026-12-31', '21:00'), DateTime.utc(2027, 1, 1, 2));
  });

  test('tryParse rechaza formatos y fechas inexistentes', () {
    for (final (fecha, hora) in [
      ('2026-02-30', '09:00'),
      ('2026-11-05', '24:00'),
      ('5/11/2026', '09:00'),
      ('2026-11-05', '9:00'),
    ]) {
      expect(BogotaTime.tryParse(fecha, hora), isNull, reason: '$fecha $hora');
    }
  });

  test('día en Bogotá de un instante, sin importar la zona del teléfono', () {
    expect(BogotaTime.dateKey(DateTime.utc(2026, 11, 6, 4, 59)), '2026-11-05');
    expect(BogotaTime.dateKey(DateTime.utc(2026, 11, 6, 5)), '2026-11-06');
    expect(BogotaTime.wallClock(DateTime.utc(2026, 11, 6, 4, 59)).hour, 23);
    expect(BogotaTime.startOfDay(DateTime.utc(2026, 11, 6, 4)), DateTime.utc(2026, 11, 5, 5));
    expect(BogotaTime.startOfCalendarDay(DateTime(2026, 11, 6, 15)), DateTime.utc(2026, 11, 6, 5));
  });
}
