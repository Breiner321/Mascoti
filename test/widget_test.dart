import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/presentation/welcome_page.dart';

void main() {
  testWidgets('La bienvenida muestra el botón de Google', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: WelcomePage())),
    );

    expect(find.text('Te damos la bienvenida'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
  });
}
