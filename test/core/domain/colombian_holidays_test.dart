import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/colombian_holidays.dart';

void main() {
  test('festivos oficiales de Colombia 2026', () {
    expect(ColombianHolidays.forYear(2026).map((h) => h.fecha), [
      '2026-01-01', '2026-01-12', '2026-03-23', '2026-04-02', '2026-04-03', '2026-05-01',
      '2026-05-18', '2026-06-08', '2026-06-15', '2026-06-29', '2026-07-20', '2026-08-07',
      '2026-08-17', '2026-10-12', '2026-11-02', '2026-11-16', '2026-12-08', '2026-12-25',
    ]);
  });

  test('festivos oficiales de Colombia 2027', () {
    expect(ColombianHolidays.forYear(2027).map((h) => h.fecha), [
      '2027-01-01', '2027-01-11', '2027-03-22', '2027-03-25', '2027-03-26', '2027-05-01',
      '2027-05-10', '2027-05-31', '2027-06-07', '2027-07-05', '2027-07-20', '2027-08-07',
      '2027-08-16', '2027-10-18', '2027-11-01', '2027-11-15', '2027-12-08', '2027-12-25',
    ]);
  });

  test('entre dos fechas, cruzando de año', () {
    final list = ColombianHolidays.between('2026-12-01', '2027-01-15');
    expect(list.map((h) => h.toString()), [
      '2026-12-08 Inmaculada Concepción',
      '2026-12-25 Navidad',
      '2027-01-01 Año Nuevo',
      '2027-01-11 Día de los Reyes Magos',
    ]);
  });
}
