import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/presentation/pet_profile_page.dart';
import 'package:mascoti/plugins/mascotas/presentation/pets_providers.dart';

void main() {
  Future<void> pumpProfile(WidgetTester tester, Stream<Pet?> pet) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [petProvider('p1').overrideWith((ref) => pet)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const PetProfilePage(petId: 'p1'),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('muestra los datos, Editar y las pestañas preparadas', (tester) async {
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
    expect(find.text('Próximamente'), findsOneWidget);
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
}
