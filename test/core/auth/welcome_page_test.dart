import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/data/auth_repository.dart';
import 'package:mascoti/core/auth/domain/auth_failure.dart';
import 'package:mascoti/core/auth/presentation/welcome_page.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;

  setUp(() => repository = _MockAuthRepository());

  Future<void> pumpPage(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(theme: AppTheme.light(), home: const WelcomePage()),
        ),
      );

  Future<void> tapGoogle(WidgetTester tester) async {
    await tester.tap(find.text('Continuar con Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('muestra los textos del mockup LOGIN', (tester) async {
    await pumpPage(tester);
    expect(find.text('Te damos la bienvenida'), findsOneWidget);
    expect(find.text('Cuidado, citas y tienda para tu mascota en un solo lugar.'),
        findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
  });

  testWidgets('cerrar el selector de Google no muestra errores', (tester) async {
    when(() => repository.signInWithGoogle()).thenAnswer((_) async => false);
    await pumpPage(tester);
    await tapGoogle(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('sin red: mensaje con "Reintentar"', (tester) async {
    when(() => repository.signInWithGoogle())
        .thenThrow(const AuthFailure(AuthFailureKind.network));
    await pumpPage(tester);
    await tapGoogle(tester);
    expect(
      find.text('No se pudo completar el inicio de sesión. Verifica tu conexión'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('cuenta suspendida: mensaje del RF-02 sin "Reintentar"',
      (tester) async {
    when(() => repository.signInWithGoogle())
        .thenThrow(const AuthFailure(AuthFailureKind.suspended));
    await pumpPage(tester);
    await tapGoogle(tester);
    expect(find.text('Tu cuenta ha sido suspendida. Contacta a soporte'),
        findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });
}
