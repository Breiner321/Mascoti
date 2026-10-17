import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/patient_code.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/data/pets_repository.dart';
import 'package:mascoti/plugins/mascotas/presentation/pets_providers.dart';
import 'package:mascoti/plugins/mascotas/presentation/widgets/patient_access_card.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('clinics/c1').set({
      'ownerUid': 'vet',
      'nombre': 'Vet Norte',
      'direccion': 'Calle 100, Bogotá',
      'estado': 'activo',
    });
  });

  Future<void> pumpCard(WidgetTester tester, String petId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          petsRepositoryProvider.overrideWithValue(PetsRepository(firestore: firestore)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final pet = ref.watch(petProvider(petId)).value;
                return pet == null
                    ? const SizedBox()
                    : SingleChildScrollView(child: PatientAccessCard(pet: pet));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el código y las clínicas con acceso', (tester) async {
    await firestore.doc('pets/p1').set({
      'ownerUid': 'ana',
      'nombre': 'Luna',
      'especie': 'perro',
      'codigoPaciente': 'MSC-7K4P',
      'clinicasAutorizadas': ['c1'],
    });
    await pumpCard(tester, 'p1');

    expect(find.text('MSC-7K4P'), findsOneWidget);
    expect(find.byTooltip('Copiar código'), findsOneWidget);
    expect(find.text('Vet Norte'), findsOneWidget);
    expect(find.text('Calle 100, Bogotá'), findsOneWidget);
  });

  testWidgets('sin clínicas autorizadas lo dice', (tester) async {
    await firestore.doc('pets/p1').set({
      'ownerUid': 'ana',
      'nombre': 'Luna',
      'especie': 'perro',
      'codigoPaciente': 'MSC-7K4P',
    });
    await pumpCard(tester, 'p1');
    expect(find.text('Ninguna clínica tiene acceso todavía.'), findsOneWidget);
  });

  testWidgets('a una mascota de la semana 2 le asigna el código al abrirla',
      (tester) async {
    await firestore.doc('pets/p1').set({'ownerUid': 'ana', 'nombre': 'Luna', 'especie': 'perro'});
    await pumpCard(tester, 'p1');

    final code = (await firestore.doc('pets/p1').get()).data()!['codigoPaciente'] as String?;
    expect(PatientCode.isValid(code), isTrue);
    expect(find.text(code!), findsOneWidget);
  });

  testWidgets('quitar el acceso pide confirmación y revoca la clínica', (tester) async {
    await firestore.doc('pets/p1').set({
      'ownerUid': 'ana',
      'nombre': 'Luna',
      'especie': 'perro',
      'codigoPaciente': 'MSC-7K4P',
      'clinicasAutorizadas': ['c1'],
    });
    await pumpCard(tester, 'p1');

    await tester.tap(find.text('Quitar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ya no podrá ver a Luna'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Quitar acceso'));
    await tester.pumpAndSettle();

    expect((await firestore.doc('pets/p1').get()).data()!['clinicasAutorizadas'], isEmpty);
    expect(find.text('Ninguna clínica tiene acceso todavía.'), findsOneWidget);
    expect(find.text('Vet Norte ya no tiene acceso'), findsOneWidget);
  });

  test('Pet sin código no rompe el resumen', () {
    const pet = Pet(id: 'p', ownerUid: 'a', nombre: 'X', especie: PetSpecies.gato);
    expect(pet.codigoPaciente, isNull);
  });
}
