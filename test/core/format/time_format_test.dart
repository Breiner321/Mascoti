import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/format/time_format.dart';

void main() {
  test('convierte horas de 24 h a AM/PM', () {
    expect(TimeFormat.hour('00:00'), '12:00 a. m.');
    expect(TimeFormat.hour('00:15'), '12:15 a. m.');
    expect(TimeFormat.hour('08:05'), '8:05 a. m.');
    expect(TimeFormat.hour('11:59'), '11:59 a. m.');
    expect(TimeFormat.hour('12:00'), '12:00 p. m.');
    expect(TimeFormat.hour('13:50'), '1:50 p. m.');
    expect(TimeFormat.hour('23:30'), '11:30 p. m.');
  });

  test('textos que no son horas válidas se devuelven tal cual', () {
    expect(TimeFormat.hour('25:00'), '25:00');
    expect(TimeFormat.hour('mediodía'), 'mediodía');
  });

  test('rango y TimeOfDay', () {
    expect(TimeFormat.range('08:00', '18:00'), '8:00 a. m. – 6:00 p. m.');
    expect(TimeFormat.ofTime(const TimeOfDay(hour: 21, minute: 7)), '9:07 p. m.');
  });

  testWidgets('el selector de hora usa AM/PM aunque el teléfono use 24 h',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(alwaysUse24HourFormat: true),
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => TimeFormat.pick(
              context,
              initialTime: const TimeOfDay(hour: 15, minute: 0),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('PM'), findsOneWidget);
    expect(find.text('AM'), findsOneWidget);
  });
}
