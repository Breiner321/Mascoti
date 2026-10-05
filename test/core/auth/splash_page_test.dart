import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/session_state.dart';
import 'package:mascoti/core/auth/presentation/splash_page.dart';

void main() {
  Future<void> pumpSplash(WidgetTester tester, SessionState session) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWithValue(session)],
          child: const MaterialApp(home: SplashPage()),
        ),
      );

  testWidgets('cargando: solo el indicador al principio', (tester) async {
    await pumpSplash(tester, const SessionLoading());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('si el servidor no responde, avisa con "Reintentar"',
      (tester) async {
    await pumpSplash(tester, const SessionLoading());
    await tester.pump(SplashPage.slowAfter);

    expect(find.text('Estamos tardando en conectar. Verifica tu conexión.'),
        findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('error de sesión: mensaje con "Reintentar"', (tester) async {
    await pumpSplash(tester, const SessionError('permission-denied'));
    expect(find.text('No pudimos cargar tu cuenta. Verifica tu conexión.'),
        findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
