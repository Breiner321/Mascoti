import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/data/auth_repository.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/auth/presentation/complete_profile_page.dart';
import 'package:mascoti/core/auth/presentation/edit_profile_page.dart';
import 'package:mascoti/core/auth/presentation/profile_page.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repository;

  const legacy = AppUser(
    uid: 'ana',
    email: 'ana.perez@gmail.com',
    displayName: 'ana p',
    role: UserRole.dueno,
  );
  const owner = AppUser(
    uid: 'ana',
    email: 'ana.perez@gmail.com',
    displayName: 'ana p',
    role: UserRole.dueno,
    nombre: 'Ana Pérez',
    telefono: '3001234567',
  );
  const clinic = AppUser(
    uid: 'vet',
    email: 'vet@gmail.com',
    displayName: 'Juan Google',
    role: UserRole.clinica,
    clinicId: 'c1',
  );

  setUp(() {
    repository = _MockAuthRepository();
    when(() => repository.updateOwnerProfile(
          nombre: any(named: 'nombre'),
          telefono: any(named: 'telefono'),
        )).thenAnswer((_) async {});
    when(() => repository.watchClinicName('c1')).thenAnswer((_) => Stream.value('Vet Norte'));
    when(() => repository.signOut()).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester, AppUser user, Widget page) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        authRepositoryProvider.overrideWithValue(repository),
        pluginRegistryProvider.overrideWithValue(PluginRegistry(const [])),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: page)),
    ));
    await tester.pumpAndSettle();
  }

  final nameField = find.widgetWithText(TextFormField, 'Nombre completo');
  final phoneField = find.widgetWithText(TextFormField, 'Teléfono (10 dígitos)');

  testWidgets('"Completa tu perfil" prellena con Google, exige teléfono y guarda', (tester) async {
    await pump(tester, legacy, const CompleteProfilePage());

    expect(find.text('Completa tu perfil'), findsOneWidget);
    expect(find.text('ana p'), findsOneWidget);
    expect(find.text('ana.perez@gmail.com'), findsNothing);

    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('El teléfono es obligatorio'), findsOneWidget);
    verifyNever(() => repository.updateOwnerProfile(
          nombre: any(named: 'nombre'), telefono: any(named: 'telefono')));

    await tester.enterText(nameField, 'Ana Pérez');
    await tester.enterText(phoneField, '3001234567');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    verify(() => repository.updateOwnerProfile(nombre: 'Ana Pérez', telefono: '3001234567'))
        .called(1);

    await tester.tap(find.text('Cerrar sesión'));
    verify(() => repository.signOut()).called(1);
  });

  testWidgets('"Editar perfil" precarga los datos del dueño y muestra el error del servidor',
      (tester) async {
    when(() => repository.updateOwnerProfile(
          nombre: any(named: 'nombre'),
          telefono: any(named: 'telefono'),
        )).thenThrow(const ProfileUpdateFailure('No se pudieron guardar tus datos. Intenta de nuevo'));
    await pump(tester, owner, const EditProfilePage());

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('3001234567'), findsOneWidget);

    await tester.enterText(nameField, 'Ana María Pérez');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron guardar tus datos. Intenta de nuevo'), findsOneWidget);
  });

  testWidgets('el perfil muestra el nombre del dueño, no el de Google', (tester) async {
    await pump(tester, owner, const ProfilePage());
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('ana p'), findsNothing);
    expect(find.text('Editar perfil'), findsOneWidget);
  });

  testWidgets('la clínica se muestra con su nombre comercial y sin "Editar perfil"',
      (tester) async {
    await pump(tester, clinic, const ProfilePage());
    expect(find.text('Vet Norte'), findsOneWidget);
    expect(find.text('Juan Google'), findsNothing);
    expect(find.text('Editar perfil'), findsNothing);
  });
}
