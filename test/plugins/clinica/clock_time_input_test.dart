import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/clinica/presentation/clock_time_input.dart';

import '../../a11y.dart';

void main() {
  late List<String> changes;

  setUp(() => changes = []);

  Future<void> pump(
    WidgetTester tester, {
    String value = '08:00',
    int step = 30,
    bool enabled = true,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.of(AppPalette.light),
      home: Scaffold(
        body: ClockTimeInput(
          label: 'Abre',
          semanticLabel: 'Abre el Lunes',
          value: value,
          stepMinutes: step,
          enabled: enabled,
          onChanged: changes.add,
        ),
      ),
    ));
  }

  Future<void> choose(WidgetTester tester, String current, String option) async {
    await tester.tap(find.text(current));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('muestra la hora en 12 h con a. m. / p. m.', (tester) async {
    await pump(tester, value: '18:30');
    expect(find.text('6'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    final period = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(period.selected, {true});
  });

  testWidgets('elegir hora, minutos y p. m. guarda en 24 h', (tester) async {
    await pump(tester, value: '08:00');

    await choose(tester, '8', '9');
    expect(changes.last, '09:00');

    await choose(tester, '00', '30');
    expect(changes.last, '08:30');

    await tester.tap(find.text('p. m.'));
    await tester.pump();
    expect(changes.last, '20:00');
  });

  testWidgets('12 a. m. es medianoche y 12 p. m. es mediodía', (tester) async {
    await pump(tester, value: '12:00');
    await tester.tap(find.text('a. m.'));
    await tester.pump();
    expect(changes.last, '00:00');

    await pump(tester, value: '00:00');
    await tester.tap(find.text('p. m.'));
    await tester.pump();
    expect(changes.last, '12:00');
  });

  testWidgets('solo ofrece los minutos de la franja (y el guardado si no encaja)', (tester) async {
    await pump(tester, value: '08:00', step: 15);
    await tester.tap(find.text('00'));
    await tester.pumpAndSettle();
    for (final m in ['15', '30', '45']) {
      expect(find.text(m), findsWidgets, reason: m);
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await pump(tester, value: '12:30', step: 60);
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    expect(find.text('00'), findsWidgets);
    expect(find.text('15'), findsNothing);
  });

  testWidgets('deshabilitado no cambia nada', (tester) async {
    await pump(tester, enabled: false);
    await tester.tap(find.text('p. m.'));
    await tester.pump();
    expect(changes, isEmpty);
  });

  group('accesibilidad', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await pump(tester);
      await expectAccessible(tester);
      expect(find.bySemanticsLabel(RegExp('Abre el Lunes')), findsOneWidget);
    });

    testWidgets('modo oscuro', (tester) async {
      addTearDown(() => AppTheme.of(AppPalette.light));
      await pump(tester, theme: AppTheme.of(AppPalette.dark));
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      useLargeText(tester);
      await pump(tester, value: '18:30');
      expectNoOverflow(tester);
    });
  });
}
