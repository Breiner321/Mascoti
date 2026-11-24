import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/qr_tags_providers.dart';
import 'package:mascoti/core/data/qr_tags_repository.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/domain/qr_tag.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/presentation/documents_tab.dart';
import 'package:mascoti/plugins/mascotas/presentation/pets_providers.dart';
import 'package:mascoti/plugins/mascotas/presentation/qr_share.dart';

import '../../a11y.dart';

const owner = AppUser(
  uid: 'ana',
  email: 'ana@example.com',
  displayName: 'ana.p',
  role: UserRole.dueno,
  nombre: 'Ana Pérez',
  telefono: '3001234567',
);

const luna = Pet(
  id: 'p1',
  ownerUid: 'ana',
  nombre: 'Luna',
  especie: PetSpecies.perro,
  fotoPath: 'ana/p1/foto.jpg',
  alergias: ['Pollo'],
);

void main() {
  late FakeFirebaseFirestore firestore;
  late List<String> shared;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    shared = [];
  });

  Future<void> pump(WidgetTester tester, {Pet pet = luna, ThemeData? theme}) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(owner),
        qrTagsRepositoryProvider.overrideWithValue(QrTagsRepository(firestore: firestore)),
        // Sin red: la foto no carga (se ve la huella).
        petPhotoUrlProvider.overrideWith((ref, path) => Future.error('sin red')),
        qrImageSharerProvider.overrideWithValue((Uint8List png, String name) async {
          shared.add(name);
        }),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: Scaffold(body: DocumentsTab(pet: pet)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> seedTag({bool activo = true}) => firestore.doc('qrTags/abcDEF234567').set({
        'petId': 'p1',
        'ownerUid': 'ana',
        'activo': activo,
        'mostrar': const QrTagDisplay(mensaje: 'Recompensa').toMap(),
        'createdAt': DateTime(2026, 11, 20),
      });

  testWidgets('la pestaña tiene la placa QR y el lugar del carnet', (tester) async {
    await pump(tester);
    expect(find.text('Placa QR'), findsOneWidget);
    expect(find.text('Carnet de vacunas (PDF)'), findsOneWidget);
    expect(find.text('Crear placa QR'), findsOneWidget);
  });

  testWidgets('sin foto pide agregarla antes de crear la placa', (tester) async {
    await pump(tester, pet: const Pet(id: 'p1', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.perro));
    expect(find.text('Crear placa QR'), findsNothing);
    expect(find.text('Agregar foto'), findsOneWidget);
  });

  testWidgets('crear: interruptores, vista previa y guardado', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Crear placa QR'));
    await tester.pumpAndSettle();

    expect(find.text('Esto verá quien escanee la placa'), findsOneWidget);
    // Teléfono enmascarado en la vista previa.
    expect(find.textContaining('300 *** **67'), findsWidgets);
    expect(find.text('Ana Pérez'), findsWidgets);

    // Ocultar el teléfono y sin mensaje: no hay contacto → error.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Mi teléfono'));
    await tester.pumpAndSettle();
    expect(find.textContaining('300 *** **67 (se ve'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Crear placa QR').last);
    await tester.pumpAndSettle();
    expect(find.text('Muestra tu teléfono o escribe un mensaje para que puedan contactarte.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Hay recompensa');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear placa QR').last);
    await tester.pumpAndSettle();

    final docs = (await firestore.collection('qrTags').get()).docs;
    expect(docs, hasLength(1));
    expect(docs.single.id, matches(RegExp(r'^[A-Za-z0-9]{12}$')));
    expect(docs.single.data()['mostrar'], {
      'nombreDueno': true,
      'telefono': false,
      'alergias': true,
      'mensaje': 'Hay recompensa',
    });
    expect(find.text('Activa'), findsOneWidget);
    expect(find.text('Compartir imagen'), findsOneWidget);
  });

  testWidgets('con placa: QR descrito para TalkBack, compartir y desactivar', (tester) async {
    await seedTag();
    await pump(tester);

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('Código QR de la placa de Luna')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Estado: Activa')), findsOneWidget);
    handle.dispose();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Compartir imagen'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(shared, ['placa_luna.png']);

    await tester.tap(find.text('Desactivar placa'));
    await tester.pumpAndSettle();
    expect(find.text('¿Desactivar la placa?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Desactivar placa'));
    await tester.pumpAndSettle();

    expect((await firestore.doc('qrTags/abcDEF234567').get()).data()!['activo'], isFalse);
    expect(find.text('Desactivada'), findsOneWidget);
    expect(find.byIcon(Icons.block), findsWidgets);
    expect(find.text('Volver a activar'), findsOneWidget);
    expect(find.text('Compartir imagen'), findsNothing);
  });

  testWidgets('cancelar la confirmación no desactiva', (tester) async {
    await seedTag();
    await pump(tester);
    await tester.tap(find.text('Desactivar placa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect((await firestore.doc('qrTags/abcDEF234567').get()).data()!['activo'], isTrue);
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await seedTag();
      await pump(tester);
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      useLargeText(tester);
      await seedTag();
      await pump(tester);
      expectNoOverflow(tester);
      await tester.tap(find.text('Qué se muestra'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
    });

    testWidgets('modo oscuro', (tester) async {
      AppColors.palette = AppPalette.dark;
      addTearDown(() => AppColors.palette = AppPalette.light);
      await seedTag(activo: false);
      await pump(tester, theme: AppTheme.of(AppPalette.dark));
      expect(find.text('Desactivada'), findsOneWidget);
      await expectAccessible(tester);
    });
  });

  test('id aleatorio, enmascarado y nombre del archivo', () {
    expect(QrTag.newId(), matches(RegExp(r'^[A-Za-z0-9]{12}$')));
    expect(QrTag.newId() == QrTag.newId(), isFalse);
    expect(maskPhone('3001234567'), '300 *** **67');
    expect(plateFileName('Ñoño Pérez'), 'placa_nono_perez.png');
    expect(const QrTagDisplay().validate(hasPhoto: false, ownerHasPhone: true), isNotNull);
    expect(const QrTagDisplay(telefono: false).validate(hasPhoto: true, ownerHasPhone: false),
        'Escribe un mensaje de contacto o agrega tu teléfono en Perfil.');
    expect(const QrTagDisplay().validate(hasPhoto: true, ownerHasPhone: true), isNull);
  });
}
