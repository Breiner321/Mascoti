import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/domain/product.dart';
import 'package:mascoti/core/images/photo_compression.dart';
import 'package:mascoti/core/storage/storage_providers.dart';
import 'package:mascoti/core/storage/storage_repository.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/tienda/presentation/clinica/clinic_shop_providers.dart';
import 'package:mascoti/plugins/tienda/presentation/clinica/product_form_page.dart';

import '../../a11y.dart';
import 'clinic_shop_test_utils.dart';

/// PNG de 1×1 píxel.
const _pixel = [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  100,
  248,
  207,
  80,
  15,
  0,
  3,
  134,
  1,
  128,
  90,
  52,
  125,
  107,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

class _FakePicker implements PhotoPicker {
  _FakePicker({this.error});

  final PhotoException? error;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    if (error != null) throw error!;
    return PickedPhoto(bytes: Uint8List.fromList(_pixel));
  }
}

/// Falla las primeras [failures] subidas (como sin red).
class _FakeStorage extends StorageRepository {
  _FakeStorage() : super(null);

  int failures = 0;
  final uploads = <String>[];

  @override
  Future<String> uploadProductPhoto({
    required String clinicUid,
    required String productId,
    required Uint8List bytes,
    bool png = false,
  }) async {
    if (failures > 0) {
      failures--;
      throw Exception('unavailable');
    }
    final path = StorageRepository.productPhotoPath(clinicUid, productId, png: png);
    uploads.add(path);
    return path;
  }

  @override
  Future<String> signedUrl(String fullPath,
          {String bucketId = StorageRepository.bucket,
          Duration expiresIn = const Duration(hours: 1)}) =>
      Future.error(StateError('sin red'));
}

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingShopRepository repo;
  late _FakeStorage storage;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RecordingShopRepository(firestore);
    storage = _FakeStorage();
  });

  Future<GoRouter> pump(
    WidgetTester tester, {
    String? productId,
    PhotoPicker? picker,
    ThemeData? theme,
  }) async {
    final router = await pumpClinicShop(
      tester,
      home: const Scaffold(body: Text('Inventario')),
      repository: repo,
      theme: theme,
      height: 5000,
      overrides: [
        storageRepositoryProvider.overrideWithValue(storage),
        productPhotoPickerProvider.overrideWithValue(picker ?? _FakePicker()),
      ],
      extraRoutes: {
        '/form': (_) => const ProductFormPage(),
        '/form/:id': (state) => ProductFormPage(productId: state.pathParameters['id']),
      },
    );
    router.push(productId == null ? '/form' : '/form/$productId');
    await tester.pumpAndSettle();
    return router;
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> pickPhoto(WidgetTester tester) async {
    await tester.tap(find.text('Agregar foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir de la galería'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseCategory(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<ProductCategory>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String nombre = 'Collar', String stock = '5'}) async {
    await tester.enterText(field('Nombre'), nombre);
    await chooseCategory(tester, 'Accesorio');
    await tester.enterText(field('Precio'), '45000');
    await tester.enterText(field('Stock inicial'), stock);
    await tester.pumpAndSettle();
  }

  group('validaciones', () {
    testWidgets('campos obligatorios y foto obligatoria', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Publicar Producto'));
      await tester.pumpAndSettle();

      expect(find.text('El nombre es obligatorio'), findsOneWidget);
      expect(find.text('Elige una categoría'), findsOneWidget);
      expect(find.text('Ingresa un precio en pesos, sin decimales'), findsOneWidget);
      expect(find.text('Ingresa un número entero'), findsOneWidget);
      expect(find.text('Agrega una foto del producto'), findsOneWidget);
      expect((await firestore.collection('clinics/c1/products').get()).docs, isEmpty);
    });

    testWidgets('nombre de 3 a 60 caracteres y precio mayor que 0', (tester) async {
      await pump(tester);
      await tester.enterText(field('Nombre'), 'ab');
      await tester.enterText(field('Precio'), '0');
      await tester.tap(find.text('Publicar Producto'));
      await tester.pumpAndSettle();

      expect(find.text('El nombre debe tener entre 3 y 60 caracteres'), findsOneWidget);
      expect(find.text('El precio debe ser mayor que 0'), findsOneWidget);
    });

    testWidgets('las categorías son las del RF', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(DropdownButtonFormField<ProductCategory>));
      await tester.pumpAndSettle();
      for (final label in ['Alimento', 'Juguete', 'Accesorio', 'Medicamento OTC']) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('un archivo no válido muestra el error y pide otro', (tester) async {
      await pump(tester, picker: _FakePicker(error: PhotoException.unsupported));
      await pickPhoto(tester);
      expect(find.text(PhotoException.unsupported.message), findsOneWidget);
    });

    testWidgets('advierte (sin bloquear) un nombre muy parecido', (tester) async {
      await addProduct(firestore, 'a', 'Collar antipulgas');
      await pump(tester);
      await tester.enterText(field('Nombre'), 'Collar antipulga');
      await tester.pumpAndSettle();
      expect(find.text('Ya tienes un producto muy parecido: "Collar antipulgas"'), findsOneWidget);
    });
  });

  testWidgets('publica el producto con la foto en la carpeta de la clínica', (tester) async {
    await pump(tester);
    await pickPhoto(tester);
    await fill(tester, stock: '0');
    await tester.tap(find.text('Publicar Producto'));
    await tester.pumpAndSettle();

    final docs = (await firestore.collection('clinics/c1/products').get()).docs;
    final data = docs.single.data();
    expect(data['nombre'], 'Collar');
    expect(data['categoria'], 'accesorio');
    expect(data['precio'], 45000);
    expect(data['fotoPath'], 'vet/${docs.single.id}.jpg');
    // Stock 0 → agotado.
    expect(data['estado'], 'agotado');
    expect(find.text('Inventario'), findsOneWidget);
  });

  testWidgets('si la foto no sube, muestra el error y reintenta', (tester) async {
    storage.failures = 1;
    await pump(tester);
    await pickPhoto(tester);
    await fill(tester);
    await tester.tap(find.text('Publicar Producto'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo subir la foto. Verifica tu conexión.'), findsOneWidget);
    expect((await firestore.collection('clinics/c1/products').get()).docs, isEmpty);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(storage.uploads, hasLength(1));
    expect((await firestore.collection('clinics/c1/products').get()).docs, hasLength(1));
  });

  testWidgets('editar: reponer stock quita "agotado" y se puede desactivar', (tester) async {
    await addProduct(firestore, 'p1', 'Collar', stock: 0);
    await pump(tester, productId: 'p1');

    expect(find.text('Editar producto'), findsOneWidget);
    await tester.enterText(field('Stock'), '4');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    var data = (await firestore.doc('clinics/c1/products/p1').get()).data()!;
    expect(data['stock'], 4);
    expect(data['estado'], 'activo');
    expect(data['fotoPath'], 'vet/p1.jpg');

    await pump(tester, productId: 'p1');
    await tester.tap(find.text('Desactivar producto'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
    await tester.pumpAndSettle();
    data = (await firestore.doc('clinics/c1/products/p1').get()).data()!;
    expect(data['estado'], 'inactivo');
  });

  testWidgets('accesible, al 200 % y en modo oscuro', (tester) async {
    useLargeText(tester);
    await pump(tester, theme: AppTheme.of(AppPalette.dark));
    expectNoOverflow(tester);
    await expectAccessible(tester);
  });
}
