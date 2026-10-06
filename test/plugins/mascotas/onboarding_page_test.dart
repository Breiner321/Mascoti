import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/data/auth_repository.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/mascotas_plugin.dart';
import 'package:mascoti/plugins/mascotas/mascotas_routes.dart';
import 'package:mascoti/plugins/mascotas/presentation/onboarding_page.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;

  const owner = AppUser(
    uid: 'u1',
    email: 'ana@correo.co',
    displayName: 'Ana',
    role: UserRole.dueno,
  );

  setUp(() => repository = _MockAuthRepository());

  Future<void> pumpOnboarding(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: MascotasRoutes.onboarding,
      routes: [
        GoRoute(
          path: MascotasRoutes.onboarding,
          builder: (context, state) => const OnboardingPage(),
        ),
        GoRoute(
          path: MascotasRoutes.home,
          builder: (context, state) => const Text('HOME'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          currentUserProvider.overrideWithValue(owner),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipeLeft(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
  }

  testWidgets('"Saltar" marca el onboarding como visto y va al home',
      (tester) async {
    await pumpOnboarding(tester);
    expect(find.text('Agenda citas'), findsOneWidget);

    await tester.tap(find.text('Saltar'));
    await tester.pumpAndSettle();

    verify(() => repository.markOnboardingSeen()).called(1);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('se recorren los 3 pasos deslizando y "Empezar" termina',
      (tester) async {
    await pumpOnboarding(tester);
    expect(find.text('Empezar'), findsNothing);

    await swipeLeft(tester);
    expect(find.text('El historial de tu mascota'), findsOneWidget);
    expect(find.text('Empezar'), findsNothing);

    await swipeLeft(tester);
    expect(find.text('Botón SOS'), findsOneWidget);
    expect(find.text('Empezar'), findsOneWidget);

    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();

    verify(() => repository.markOnboardingSeen()).called(1);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('"Siguiente" avanza de paso', (tester) async {
    await pumpOnboarding(tester);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('El historial de tu mascota'), findsOneWidget);
    verifyNever(() => repository.markOnboardingSeen());
  });

  test('el plugin exige el onboarding solo si no se ha visto', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const plugin = MascotasPlugin();

    final pending = plugin.requiredStep(owner)!;
    expect(container.read(pending).value, MascotasRoutes.onboarding);

    const seen = AppUser(
      uid: 'u1',
      email: 'ana@correo.co',
      displayName: 'Ana',
      role: UserRole.dueno,
      onboardingVisto: true,
    );
    expect(container.read(plugin.requiredStep(seen)!).value, isNull);
  });
}
