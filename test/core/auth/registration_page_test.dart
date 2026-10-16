import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/data/auth_repository.dart';
import 'package:mascoti/core/auth/domain/registration.dart';
import 'package:mascoti/core/auth/domain/registration_failure.dart';
import 'package:mascoti/core/auth/domain/session_state.dart';
import 'package:mascoti/core/auth/presentation/registration_page.dart';
import 'package:mascoti/core/places/places_providers.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';

import '../fakes/fake_address_search.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;

  setUpAll(() => registerFallbackValue(const RegistrationRequest.owner()));

  setUp(() {
    repository = _MockAuthRepository();
    when(() => repository.completeRegistration(any())).thenAnswer((_) async {});
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(
            const NeedsRegistration(uid: 'u1', email: 'vet@correo.co'),
          ),
          authRepositoryProvider.overrideWithValue(repository),
          addressSearchServiceProvider.overrideWithValue(FakeAddressSearch()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const RegistrationPage()),
      ),
    );
  }

  final submit = find.widgetWithText(FilledButton, 'Finalizar Registro');
  final nameField = find.widgetWithText(TextFormField, 'Nombre comercial');
  final phoneField = find.widgetWithText(TextFormField, 'Teléfono (10 dígitos)');
  final addressField = find.widgetWithText(TextField, 'Dirección');

  bool isEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(submit).onPressed != null;

  Future<void> chooseRole(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> fillClinic(WidgetTester tester) async {
    await tester.enterText(nameField, 'Vet Norte');
    await tester.enterText(phoneField, '3001234567');
  }

  Future<void> pickAddress(WidgetTester tester) async {
    await tester.enterText(addressField, 'Calle 100');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Calle 100 # 15-20'));
    await tester.pumpAndSettle();
  }

  Future<RegistrationRequest> sentRequest() async =>
      verify(() => repository.completeRegistration(captureAny()))
          .captured
          .single as RegistrationRequest;

  testWidgets('muestra el correo y las tarjetas del mockup', (tester) async {
    await pumpPage(tester);
    expect(find.text('vet@correo.co'), findsOneWidget);
    expect(find.text('¿CÓMO USARÁS MASCOTI?'), findsOneWidget);
    expect(find.text('Dueño de Mascota'), findsOneWidget);
    expect(find.text('Clínica Veterinaria'), findsOneWidget);
  });

  testWidgets('"Finalizar Registro" está deshabilitado sin rol (RF-01 paso 8)',
      (tester) async {
    await pumpPage(tester);
    expect(isEnabled(tester), isFalse);

    await chooseRole(tester, 'Dueño de Mascota');
    expect(isEnabled(tester), isTrue);
  });

  testWidgets('el dueño se registra sin formulario adicional', (tester) async {
    await pumpPage(tester);
    await chooseRole(tester, 'Dueño de Mascota');
    expect(nameField, findsNothing);

    await tester.tap(submit);
    await tester.pump();

    expect((await sentRequest()).toMap(), {'role': 'dueno'});
  });

  testWidgets('la clínica ve los errores de validación y no se envía',
      (tester) async {
    await pumpPage(tester);
    await chooseRole(tester, 'Clínica Veterinaria');

    await tester.tap(submit);
    await tester.pump();
    expect(find.text('El nombre comercial es obligatorio'), findsOneWidget);
    expect(find.text('El teléfono es obligatorio'), findsOneWidget);
    expect(find.text('Selecciona una dirección válida de la lista'), findsOneWidget);

    await tester.enterText(nameField, 'Ve');
    await tester.enterText(phoneField, '300123');
    await tester.pump();
    expect(find.text('Mínimo 3 caracteres'), findsOneWidget);
    expect(find.text('Debe tener 10 dígitos numéricos'), findsOneWidget);

    verifyNever(() => repository.completeRegistration(any()));
  });

  testWidgets('una dirección escrita a mano (sin escoger de la lista) bloquea el envío',
      (tester) async {
    await pumpPage(tester);
    await chooseRole(tester, 'Clínica Veterinaria');
    await fillClinic(tester);
    await tester.enterText(addressField, 'Mi casa');

    await tester.tap(submit);
    await tester.pump();

    expect(find.text('Selecciona una dirección válida de la lista'), findsOneWidget);
    verifyNever(() => repository.completeRegistration(any()));
  });

  testWidgets('la clínica se registra con lat/lng de OpenStreetMap',
      (tester) async {
    await pumpPage(tester);
    await chooseRole(tester, 'Clínica Veterinaria');
    await fillClinic(tester);
    await pickAddress(tester);

    await tester.tap(submit);
    await tester.pump();

    expect((await sentRequest()).toMap()['clinica'], {
      'nombre': 'Vet Norte',
      'telefono': '3001234567',
      'direccion': bogotaAddress.direccion,
      'lat': bogotaAddress.lat,
      'lng': bogotaAddress.lng,
    });
  });

  testWidgets('error de red muestra el mensaje con "Reintentar"', (tester) async {
    when(() => repository.completeRegistration(any())).thenThrow(
      const RegistrationFailure(RegistrationFailureKind.network),
    );
    await pumpPage(tester);
    await chooseRole(tester, 'Dueño de Mascota');
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No se pudo completar el registro. Verifica tu conexión'),
        findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    // "Reintentar" vuelve a llamar a la Function.
    when(() => repository.completeRegistration(any())).thenAnswer((_) async {});
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    verify(() => repository.completeRegistration(any())).called(2);
  });

  testWidgets('una cuenta ya registrada muestra el aviso del RF', (tester) async {
    when(() => repository.completeRegistration(any())).thenThrow(
      const RegistrationFailure(RegistrationFailureKind.alreadyExists),
    );
    await pumpPage(tester);
    await chooseRole(tester, 'Dueño de Mascota');
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Esta cuenta ya está registrada. Iniciando sesión...'),
        findsOneWidget);
  });
}
