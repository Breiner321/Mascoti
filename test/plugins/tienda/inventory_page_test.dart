import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/order.dart';
import 'package:mascoti/core/domain/product.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/tienda/presentation/clinica/inventory_page.dart';

import '../../a11y.dart';
import 'clinic_shop_test_utils.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingShopRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RecordingShopRepository(firestore);
  });

  Future<void> seed() async {
    await addProduct(firestore, 'a', 'Collar antipulgas', stock: 10);
    await addProduct(firestore, 'b', 'Concentrado cachorro', stock: 0);
    await addProduct(firestore, 'c', 'Pelota', stock: 2);
    await addProduct(firestore, 'd', 'Champú', stock: 5, estado: ProductStatus.inactivo);
  }

  Future<void> pump(WidgetTester tester, {ThemeData? theme}) => pumpClinicShop(tester,
      home: const InventoryPage(), repository: repo, theme: theme, height: 6000);

  testWidgets('estado vacío con el botón para agregar el primero', (tester) async {
    await pump(tester);

    expect(find.text('Aún no tienes productos. Agrega el primero'), findsOneWidget);
    expect(find.text('Nuevo Producto'), findsWidgets);
    await expectAccessible(tester);
  });

  testWidgets('lista productos con precio, stock y estado con texto', (tester) async {
    await seed();
    await pump(tester);

    expect(find.text('Collar antipulgas'), findsOneWidget);
    expect(find.textContaining(r'$ 45.000'), findsNWidgets(4));
    expect(find.text('Stock: 10 unidades'), findsOneWidget);
    expect(find.text('Activo'), findsNWidgets(2));
    expect(find.text('Agotado'), findsOneWidget);
    expect(find.text('Inactivo'), findsOneWidget);
    // Aviso de stock bajo (≤ 3): solo la pelota.
    expect(find.text('Stock bajo'), findsWidgets);
    expect(find.text('1 producto con stock bajo (3 unidades o menos)'), findsOneWidget);
  });

  testWidgets('busca por nombre y filtra por estado', (tester) async {
    await seed();
    await pump(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Buscar producto'), 'pelo');
    await tester.pumpAndSettle();
    expect(find.text('Pelota'), findsOneWidget);
    expect(find.text('Collar antipulgas'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Buscar producto'), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('No hay productos que coincidan con tu búsqueda.'), findsOneWidget);

    await tester.tap(find.byTooltip('Borrar búsqueda'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Agotados'));
    await tester.pumpAndSettle();
    expect(find.text('Concentrado cachorro'), findsOneWidget);
    expect(find.text('Pelota'), findsNothing);

    // El aviso de stock bajo aplica el filtro.
    await tester.tap(find.text('1 producto con stock bajo (3 unidades o menos)'));
    await tester.pumpAndSettle();
    expect(find.text('Pelota'), findsOneWidget);
    expect(find.text('Collar antipulgas'), findsNothing);
  });

  testWidgets('los botones +/− ajustan el stock sin abrir el formulario', (tester) async {
    await seed();
    await pump(tester);

    await tester.tap(find.byTooltip('Sumar una unidad de Pelota'));
    await tester.pumpAndSettle();
    var doc = (await firestore.doc('clinics/c1/products/c').get()).data()!;
    expect(doc['stock'], 3);
    expect(find.text('Stock: 3 unidades'), findsOneWidget);

    // Reponer un agotado lo vuelve a activar.
    await tester.tap(find.byTooltip('Sumar una unidad de Concentrado cachorro'));
    await tester.pumpAndSettle();
    doc = (await firestore.doc('clinics/c1/products/b').get()).data()!;
    expect(doc['estado'], 'activo');

    await tester.tap(find.byTooltip('Restar una unidad de Concentrado cachorro'));
    await tester.pumpAndSettle();
    doc = (await firestore.doc('clinics/c1/products/b').get()).data()!;
    expect(doc['estado'], 'agotado');

    // Con 0 unidades no se puede restar.
    final minus = tester.widget<IconButton>(find.ancestor(
      of: find.byTooltip('Restar una unidad de Concentrado cachorro'),
      matching: find.byType(IconButton),
    ));
    expect(minus.onPressed, isNull);
  });

  testWidgets('tocar un producto abre su edición y "Pedidos" los pedidos', (tester) async {
    await seed();
    await addOrder(firestore, sampleOrder('o1', OrderStatus.pagado));
    await pump(tester);

    expect(find.text('1'), findsOneWidget); // pedidos por preparar
    await tester.tap(find.text('Pelota'));
    await tester.pumpAndSettle();
    expect(find.text('Ruta /tienda/inventario/c/editar'), findsOneWidget);
  });

  testWidgets('accesible, al 200 % y en modo oscuro', (tester) async {
    await seed();
    useLargeText(tester);
    await pump(tester, theme: AppTheme.of(AppPalette.dark));

    expectNoOverflow(tester);
    expect(find.text('Champú'), findsOneWidget);
    await expectAccessible(tester);
  });

  testWidgets('accesible en modo claro', (tester) async {
    await seed();
    await pump(tester);
    await expectAccessible(tester);
  });
}
