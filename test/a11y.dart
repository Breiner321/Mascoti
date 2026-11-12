import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verificadores de accesibilidad de Flutter (Cambio 3): áreas táctiles de
/// 48 dp, botones con etiqueta y contraste del texto.
Future<void> expectAccessible(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

/// Texto del sistema al 200 % para la prueba que sigue. Un desborde
/// ("RenderFlex overflowed") hace fallar la prueba.
void useLargeText(WidgetTester tester, {double scale = 2.0}) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Que no haya quedado ninguna excepción de layout.
void expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byWidgetPredicate((w) => w is ErrorWidget), findsNothing);
}
