import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/order.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/tienda/presentation/clinica/clinic_order_detail_page.dart';
import 'package:mascoti/plugins/tienda/presentation/clinica/clinic_orders_page.dart';

import '../../a11y.dart';
import 'clinic_shop_test_utils.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingShopRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RecordingShopRepository(firestore);
  });

  group('pedidos recibidos', () {
    Future<void> pump(WidgetTester tester) =>
        pumpClinicShop(tester, home: const ClinicOrdersPage(), repository: repo);

    testWidgets('pestañas con contador y pedidos en tiempo real', (tester) async {
      await addOrder(firestore, sampleOrder('o1', OrderStatus.pagado));
      await addOrder(
        firestore,
        sampleOrder('o2', OrderStatus.preparando, tipo: DeliveryType.domicilio),
      );
      await addOrder(firestore, sampleOrder('o3', OrderStatus.listo));
      await addOrder(firestore, sampleOrder('o4', OrderStatus.entregado));
      // La clínica no ve pedidos sin pagar.
      await addOrder(firestore, sampleOrder('o5', OrderStatus.pendientePago));
      await pump(tester);

      expect(find.text('Por preparar (2)'), findsOneWidget);
      expect(find.text('Listos o enviados (1)'), findsOneWidget);
      expect(find.text('Historial (1)'), findsOneWidget);
      expect(find.text('Ana Pérez'), findsNWidgets(2));
      expect(find.text('2 × Collar, 1 × Pelota'), findsNWidgets(2));
      expect(find.text(r'Total: $ 100.000'), findsNWidgets(2));
      expect(find.text('Recoger en la clínica: Tel. 3001234567'), findsOneWidget);
      expect(find.text('Domicilio: Calle 10 # 20-30, Bogotá'), findsOneWidget);

      // Llega un pedido nuevo.
      await addOrder(firestore, sampleOrder('o6', OrderStatus.pagado));
      await tester.pumpAndSettle();
      expect(find.text('Por preparar (3)'), findsOneWidget);

      await tester.ensureVisible(find.text('Historial (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Historial (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Entregado'), findsOneWidget);

      await tester.tap(find.text('Ana Pérez'));
      await tester.pumpAndSettle();
      expect(find.text('Ruta /tienda/clinica/pedidos/o4'), findsOneWidget);
    });

    testWidgets('sin pedidos, accesible, al 200 % y en modo oscuro', (tester) async {
      useLargeText(tester);
      await pumpClinicShop(
        tester,
        home: const ClinicOrdersPage(),
        repository: repo,
        theme: AppTheme.of(AppPalette.dark),
      );
      expect(find.text('No tienes pedidos por preparar.'), findsOneWidget);
      expectNoOverflow(tester);
      await expectAccessible(tester);
    });
  });

  group('detalle del pedido', () {
    Future<void> pump(WidgetTester tester, ShopOrder order, {ThemeData? theme}) async {
      await addOrder(firestore, order);
      await pumpClinicShop(
        tester,
        home: ClinicOrderDetailPage(orderId: order.id, now: DateTime(2026, 11, 18, 12)),
        repository: repo,
        theme: theme,
      );
    }

    Finder button(String label) => find.widgetWithText(FilledButton, label);
    // OutlinedButton.icon crea una subclase: se busca con `is`.
    final cancelButton = find.ancestor(
      of: find.text('Cancelar pedido'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );

    final cases = {
      (OrderStatus.pagado, DeliveryType.recoger): 'Empezar a preparar',
      (OrderStatus.preparando, DeliveryType.recoger): 'Listo para recoger',
      (OrderStatus.preparando, DeliveryType.domicilio): 'Marcar como enviado',
      (OrderStatus.listo, DeliveryType.recoger): 'Entregado',
      (OrderStatus.enviado, DeliveryType.domicilio): 'Entregado',
    };
    for (final MapEntry(key: (estado, tipo), value: label) in cases.entries) {
      testWidgets('${estado.value} (${tipo.value}) → "$label"', (tester) async {
        await pump(tester, sampleOrder('o1', estado, tipo: tipo));

        expect(button(label), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        await tester.tap(button(label));
        await tester.pumpAndSettle();
        expect(repo.updates.single.$1, 'o1');
        expect(
            repo.updates.single.$2,
            estado.nextStates(tipo).firstWhere(
                  (s) => s != OrderStatus.cancelado,
                ));
        // Solo se cancela un pedido pagado o en preparación.
        expect(
          cancelButton,
          estado == OrderStatus.pagado || estado == OrderStatus.preparando
              ? findsOneWidget
              : findsNothing,
        );
      });
    }

    testWidgets('entregado o cancelado: sin botones', (tester) async {
      await pump(
        tester,
        sampleOrder('o1', OrderStatus.cancelado).copyWith(motivoCancelacion: 'Sin unidades'),
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byWidgetPredicate((w) => w is OutlinedButton), findsNothing);
      expect(find.text('Sin unidades'), findsOneWidget);
    });

    testWidgets('muestra cliente, productos, total y entrega', (tester) async {
      await pump(tester, sampleOrder('o1', OrderStatus.pagado, tipo: DeliveryType.domicilio));
      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('2 × Collar'), findsOneWidget);
      expect(find.text(r'$ 90.000'), findsOneWidget);
      expect(find.text(r'$ 100.000'), findsOneWidget);
      expect(find.text('Domicilio: Calle 10 # 20-30, Bogotá'), findsOneWidget);
      expect(find.text('Tel. 3001234567'), findsOneWidget);
      expect(find.text('Recibido: Hace 2 h'), findsOneWidget);
    });

    testWidgets('cancelar exige el motivo y avisa del reembolso', (tester) async {
      await pump(tester, sampleOrder('o1', OrderStatus.preparando));

      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('comunícate con el cliente para el reembolso'), findsOneWidget);

      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Cancelar pedido'),
      );
      // Sin motivo (o solo espacios) no se puede confirmar.
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.updates, isEmpty);

      await tester.enterText(find.byType(TextField), ' Sin unidades ');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.updates.single, ('o1', OrderStatus.cancelado, 'Sin unidades'));
    });

    testWidgets('accesible, al 200 % y en modo oscuro', (tester) async {
      useLargeText(tester);
      await pump(
        tester,
        sampleOrder('o1', OrderStatus.preparando, tipo: DeliveryType.domicilio),
        theme: AppTheme.of(AppPalette.dark),
      );
      expectNoOverflow(tester);
      await expectAccessible(tester);

      await tester.scrollUntilVisible(cancelButton, 200);
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
      await expectAccessible(tester);
    });
  });
}
