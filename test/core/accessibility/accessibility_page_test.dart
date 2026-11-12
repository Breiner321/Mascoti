import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/accessibility/accessibility_page.dart';
import 'package:mascoti/core/accessibility/accessibility_settings.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../a11y.dart';

void main() {
  late ProviderContainer container;

  Future<void> pumpPage(WidgetTester tester) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: AccessibilityPage())),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('modo oscuro, alto contraste, tamaño y animaciones se guardan en el teléfono',
      (tester) async {
    await pumpPage(tester);
    expect(container.read(accessibilitySettingsProvider), const AccessibilitySettings());

    await tester.tap(find.text('Oscuro'));
    await tester.tap(find.text('Alto contraste'));
    await tester.tap(find.text('130 %'));
    await tester.ensureVisible(find.text('Reducir animaciones'));
    await tester.tap(find.text('Reducir animaciones'));
    await tester.pumpAndSettle();

    expect(
      container.read(accessibilitySettingsProvider),
      const AccessibilitySettings(
        themeMode: ThemeMode.dark,
        highContrast: true,
        textScale: 1.3,
        reduceMotion: true,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('a11y.tema'), 'dark');
    expect(prefs.getBool('a11y.altoContraste'), isTrue);
    expect(prefs.getDouble('a11y.tamanoTexto'), 1.3);
    expect(prefs.getBool('a11y.reducirAnimaciones'), isTrue);
  });

  testWidgets('al abrir la app se cargan las preferencias guardadas', (tester) async {
    SharedPreferences.setMockInitialValues({'a11y.tema': 'dark', 'a11y.tamanoTexto': 1.15});
    await pumpPage(tester);
    final settings = container.read(accessibilitySettingsProvider);
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.textScale, 1.15);
    expect(settings.highContrast, isFalse);
  });

  testWidgets('paleta según tema y contraste', (tester) async {
    expect(AppPalette.resolve(dark: false, highContrast: false), AppPalette.light);
    expect(AppPalette.resolve(dark: true, highContrast: false), AppPalette.dark);
    expect(AppPalette.resolve(dark: true, highContrast: true), AppPalette.darkHighContrast);
    expect(AppPalette.resolve(dark: false, highContrast: true), AppPalette.lightHighContrast);
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await pumpPage(tester);
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      useLargeText(tester);
      await pumpPage(tester);
      expectNoOverflow(tester);
    });
  });
}
