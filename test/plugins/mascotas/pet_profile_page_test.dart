import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/medical_records_providers.dart';
import 'package:mascoti/core/data/qr_tags_providers.dart';
import 'package:mascoti/core/data/qr_tags_repository.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/data/health_card_repository.dart';
import 'package:mascoti/plugins/mascotas/presentation/health_card_providers.dart';
import 'package:mascoti/plugins/mascotas/presentation/pet_profile_page.dart';
import 'package:mascoti/plugins/mascotas/presentation/pets_providers.dart';

import '../../a11y.dart';

void main() {
  Future<void> pumpProfile(WidgetTester tester, Stream<Pet?> pet,
      {PetProfileTab initialTab = PetProfileTab.datos}) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          petProvider('p1').overrideWith((ref) => pet),
          medicalRecordsProvider('p1').overrideWith((ref) => Stream.value(const [])),
          currentUserProvider.overrideWithValue(const AppUser(
              uid: 'ana', email: 'ana@example.com', displayName: 'Ana', role: UserRole.dueno)),
          qrTagsRepositoryProvider
              .overrideWithValue(QrTagsRepository(firestore: FakeFirebaseFirestore())),
          healthCardRepositoryProvider
              .overrideWithValue(HealthCardRepository(firestore: FakeFirebaseFirestore())),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: PetProfilePage(petId: 'p1', initialTab: initialTab),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('muestra los datos, Editar, el historial y la pestaña de documentos', (tester) async {
    await pumpProfile(
      tester,
      Stream.value(const Pet(
        id: 'p1',
        ownerUid: 'ana',
        nombre: 'Luna',
        especie: PetSpecies.perro,
        raza: 'Criolla',
        alergias: ['Pollo'],
        contactoEmergencia: EmergencyContact(nombre: 'Ana', telefono: '3001234567'),
      )),
    );

    expect(find.text('Luna'), findsWidgets);
    expect(find.text('Criolla'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Pollo'), findsOneWidget);
    expect(find.text('Sin condiciones registradas'), findsOneWidget);
    expect(find.text('Ana · 3001234567'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Historial médico'), findsOneWidget);
    expect(find.text('Documentos'), findsOneWidget);

    await tester.tap(find.text('Historial médico'));
    await tester.pumpAndSettle();
    expect(find.text('Esta mascota aún no tiene historial médico registrado'), findsOneWidget);

    await tester.tap(find.text('Documentos'));
    await tester.pumpAndSettle();
    expect(find.text('Placa QR'), findsOneWidget);
    expect(find.text('Carnet de vacunas'), findsOneWidget);
  });

  testWidgets('?tab=documentos abre directo en Documentos (acceso "Carnet" del home)', (tester) async {
    expect(PetProfileTab.fromQuery('documentos'), PetProfileTab.documentos);
    expect(PetProfileTab.fromQuery('otra'), PetProfileTab.datos);
    expect(PetProfileTab.fromQuery(null), PetProfileTab.datos);
    await pumpProfile(
      tester,
      Stream.value(const Pet(id: 'p1', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.perro)),
      initialTab: PetProfileTab.documentos,
    );
    await tester.pumpAndSettle();
    expect(find.text('Generar carnet PDF'), findsOneWidget);
    expect(find.text('Placa QR'), findsOneWidget);
  });

  testWidgets('mascota inexistente', (tester) async {
    await pumpProfile(tester, Stream.value(null));
    expect(find.text('No encontramos esta mascota.'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);
  });

  testWidgets('error al cargar muestra "Reintentar"', (tester) async {
    await pumpProfile(tester, Stream.error(Exception('sin conexión')));
    expect(find.text('Reintentar'), findsOneWidget);
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await pumpProfile(tester, Stream.value(const Pet(
          id: 'p1', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.perro, raza: 'Criolla')));
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      useLargeText(tester);
      await pumpProfile(tester, Stream.value(const Pet(
          id: 'p1', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.perro, raza: 'Criolla')));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
    });
  });
}
