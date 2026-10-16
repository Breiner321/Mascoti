import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/data/pets_repository.dart';
import 'package:mascoti/plugins/mascotas/domain/pet_photo.dart';
import 'package:mascoti/plugins/mascotas/mascotas_routes.dart';
import 'package:mascoti/plugins/mascotas/presentation/pet_form_page.dart';
import 'package:mascoti/plugins/mascotas/presentation/pets_providers.dart';

import 'fakes.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FakePetStorage storage;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    storage = FakePetStorage();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    String location = MascotasRoutes.newPet,
    PetPhoto? photo,
  }) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(path: MascotasRoutes.newPet, builder: (_, __) => const PetFormPage()),
        GoRoute(
          path: MascotasRoutes.profilePattern,
          builder: (_, state) =>
              Scaffold(body: Text('perfil ${state.pathParameters['petId']}')),
        ),
        GoRoute(
          path: MascotasRoutes.editPattern,
          builder: (_, state) => PetFormPage(petId: state.pathParameters['petId']),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AppUser(uid: 'ana', email: '', displayName: 'Ana', role: UserRole.dueno),
          ),
          petsRepositoryProvider.overrideWithValue(
            PetsRepository(firestore: firestore, storage: storage),
          ),
          petPhotoPickerProvider.overrideWithValue(FakePhotoPicker(photo)),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> chooseSpecies(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<PetSpecies>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> addTag(WidgetTester tester, String label, String value) async {
    await tester.enterText(field(label), value);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> pets() async =>
      (await firestore.collection('pets').get()).docs;

  testWidgets('sin nombre ni especie muestra los errores y no guarda', (tester) async {
    await pumpForm(tester);

    await tester.tap(find.text('Registrar mascota'));
    await tester.pumpAndSettle();

    expect(find.text('El nombre es obligatorio'), findsOneWidget);
    expect(find.text('Selecciona la especie'), findsOneWidget);
    expect(await pets(), isEmpty);
  });

  testWidgets('el teléfono de emergencia debe tener 10 dígitos', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('Nombre *'), 'Luna');
    await chooseSpecies(tester, 'Gato');
    await tester.enterText(field('Nombre del contacto'), 'Ana');
    await tester.enterText(field('Teléfono del contacto'), '300123');

    await tester.tap(find.text('Registrar mascota'));
    await tester.pumpAndSettle();

    expect(find.text('El teléfono debe tener 10 dígitos'), findsOneWidget);
    expect(await pets(), isEmpty);
  });

  testWidgets('agrega y quita alergias como chips, sin repetidos', (tester) async {
    await pumpForm(tester);

    await addTag(tester, 'Alergias', 'Pollo');
    expect(find.widgetWithText(InputChip, 'Pollo'), findsOneWidget);

    await addTag(tester, 'Alergias', 'pollo');
    expect(find.text('Ya está en la lista'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar Pollo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Pollo'), findsNothing);
  });

  testWidgets('registra la mascota y abre su perfil', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field('Nombre *'), '  Luna ');
    await chooseSpecies(tester, 'Perro');
    await tester.enterText(field('Raza'), 'Criolla');
    await tester.tap(find.text('Hembra'));
    await addTag(tester, 'Alergias', 'Pollo');
    await addTag(tester, 'Condiciones', 'Displasia');
    await tester.enterText(field('Nombre del contacto'), 'Ana');
    await tester.enterText(field('Teléfono del contacto'), '3001234567');

    await tester.tap(find.text('Registrar mascota'));
    await tester.pumpAndSettle();

    final docs = await pets();
    expect(docs, hasLength(1));
    final data = docs.single.data();
    expect(data['ownerUid'], 'ana');
    expect(data['nombre'], 'Luna');
    expect(data['especie'], 'perro');
    expect(data['raza'], 'Criolla');
    expect(data['sexo'], 'hembra');
    expect(data['alergias'], ['Pollo']);
    expect(data['condiciones'], ['Displasia']);
    expect(data['contactoEmergencia'], {'nombre': 'Ana', 'telefono': '3001234567'});
    expect(find.text('perfil ${docs.single.id}'), findsOneWidget);
    expect(find.text('Mascota registrada'), findsOneWidget);
  });

  testWidgets(
      'si la foto no sube, guarda sin foto y muestra "Error al subir la foto" con reintento',
      (tester) async {
    storage.fail = true;
    await pumpForm(tester, photo: PetPhoto(bytes: tinyPng));

    await tester.tap(find.text('Agregar foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir de la galería'));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar foto'), findsOneWidget);

    await tester.enterText(field('Nombre *'), 'Luna');
    await chooseSpecies(tester, 'Perro');
    await tester.tap(find.text('Registrar mascota'));
    await tester.pumpAndSettle();

    final doc = (await pets()).single;
    expect(doc.data()['fotoPath'], isNull);
    expect(find.text('Error al subir la foto'), findsOneWidget);

    storage.fail = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect((await pets()).single.data()['fotoPath'], 'ana/${doc.id}/foto.jpg');
    expect(find.text('Foto guardada'), findsOneWidget);
  });

  testWidgets('edición: precarga los datos y guarda los cambios', (tester) async {
    await firestore.collection('pets').doc('p1').set(Pet(
          id: 'p1',
          ownerUid: 'ana',
          nombre: 'Luna',
          especie: PetSpecies.gato,
          alergias: const ['Pollo'],
          createdAt: DateTime(2026, 1, 1),
        ).toMap());

    await pumpForm(tester, location: MascotasRoutes.edit('p1'));

    expect(find.text('Editar mascota'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Luna'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Pollo'), findsOneWidget);

    await tester.enterText(field('Nombre *'), 'Luna Lunera');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    final data = (await firestore.collection('pets').doc('p1').get()).data()!;
    expect(data['nombre'], 'Luna Lunera');
    expect(data['especie'], 'gato');
    expect(data['alergias'], ['Pollo']);
    expect((data['createdAt'] as Timestamp).toDate(), DateTime(2026, 1, 1));
  });

  testWidgets('edición de una mascota que no existe', (tester) async {
    await pumpForm(tester, location: MascotasRoutes.edit('no-existe'));
    expect(find.text('No encontramos esta mascota.'), findsOneWidget);
  });
}
