import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/shop_repository.dart';
import 'package:mascoti/core/domain/order.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/tienda/presentation/dueno/simulated_payment_page.dart';

import '../../a11y.dart';
import 'clinic_shop_test_utils.dart';

/// Hace lo que haría el servidor (`pagar-pedido-simulado`): cambia el estado
/// del pedido en Firestore. Con [failure] responde ese error.
class _FakeShopRepository extends ShopRepository {
  _FakeShopRepository(this.firestore) : super(firestore: firestore);

  final FakeFirebaseFirestore firestore;
  final payments = <bool>[];
  ShopFailure? failure;

  @override
  Future<void> paySimulated(String orderId, {bool approve = true}) async {
    payments.add(approve);
    if (failure != null) throw failure!;
    await firestore.doc('orders/$orderId').update({
      'estado': approve ? 'pagado' : 'pago_rechazado',
      'transaccionId': 'SIM-$orderId',
    });
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 18, 15);
  late FakeFirebaseFirestore firestore;
  late _FakeShopRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = _FakeShopRepository(firestore);
  });

  ShopOrder pending({
    PaymentGateway pasarela = PaymentGateway.simulada,
    DateTime? expiraEn,
  }) =>
      ShopOrder(
        id: 'o1',
        ownerUid: 'u1',
        ownerNombre: 'Ana Pérez',
        clinicId: 'c1',
        clinicNombre: 'Vet Norte',
        items: const [
          OrderItem(productId: 'p1', nombre: 'Collar', precio: 45000, cantidad: 2),
        ],
        total: 90000,
        entrega: const OrderDelivery(tipo: DeliveryType.recoger, telefono: '3001234567'),
        estado: OrderStatus.pendientePago,
        referenciaPago: 'MSC-o1',
        pasarela: pasarela,
        expiraEn: expiraEn ?? now.add(const Duration(minutes: 15)),
      );

  Future<void> pump(WidgetTester tester, ShopOrder order, {ThemeData? theme}) async {
    await addOrder(firestore, order);
    await pumpClinicShop(
      tester,
      home: SimulatedPaymentPage(orderId: order.id, now: now),
      repository: repo,
      theme: theme,
      extraRoutes: {
        '/tienda/pedidos/:id': (state) => Text('Ruta ${state.uri}'),
        '/tienda/carrito': (state) => Text('Ruta ${state.uri}'),
      },
    );
  }

  testWidgets('muestra el aviso de prueba, el total y la hora límite', (tester) async {
    await pump(tester, pending());

    expect(find.textContaining('Pago de prueba: no se cobra dinero real'), findsOneWidget);
    expect(find.text('Vet Norte'), findsOneWidget);
    expect(find.text('2 × Collar'), findsOneWidget);
    expect(find.text(r'Pagar $ 90.000'), findsOneWidget);
    // 15:15 UTC = 10:15 a. m. en Bogotá.
    expect(find.text('Tus productos están apartados hasta las 10:15 a. m.'), findsOneWidget);
  });

  testWidgets('pagar: el pedido queda pagado y lleva al detalle', (tester) async {
    await pump(tester, pending());

    await tester.tap(find.text(r'Pagar $ 90.000'));
    await tester.pumpAndSettle();
    expect(repo.payments, [true]);
    expect(find.text('¡Pedido realizado con éxito!'), findsOneWidget);

    await tester.tap(find.text('Ver mi pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Ruta /tienda/pedidos/o1'), findsOneWidget);
  });

  testWidgets('simular rechazo: mensaje del RF y vuelta al carrito', (tester) async {
    await pump(tester, pending());

    await tester.tap(find.text('Simular pago rechazado'));
    await tester.pumpAndSettle();
    expect(repo.payments, [false]);
    expect(
      find.text('Tu pago no pudo ser procesado. Tus productos siguen en el carrito.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Volver al carrito'));
    await tester.pumpAndSettle();
    expect(find.text('Ruta /tienda/carrito'), findsOneWidget);
  });

  testWidgets('muestra el error del servidor', (tester) async {
    repo.failure = const ShopFailure('No se pudo conectar. Verifica tu conexión', canRetry: true);
    await pump(tester, pending());

    await tester.tap(find.text(r'Pagar $ 90.000'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo conectar. Verifica tu conexión'), findsOneWidget);
    expect(find.text(r'Pagar $ 90.000'), findsOneWidget);
  });

  testWidgets('vencido o de otra pasarela: no deja pagar', (tester) async {
    await pump(tester, pending(expiraEn: now.subtract(const Duration(minutes: 1))));
    expect(
      find.text('El tiempo para pagar este pedido terminó. Vuelve a confirmar la compra.'),
      findsOneWidget,
    );
    expect(find.textContaining(r'Pagar $'), findsNothing);
  });

  testWidgets('un pedido de Wompi no admite pago de prueba', (tester) async {
    await pump(tester, pending(pasarela: PaymentGateway.wompi));
    expect(find.text('Este pedido no admite pagos de prueba.'), findsOneWidget);
  });

  testWidgets('accesible, al 200 % y en modo oscuro', (tester) async {
    useLargeText(tester);
    await pump(tester, pending(), theme: AppTheme.of(AppPalette.dark));
    expectNoOverflow(tester);
    await expectAccessible(tester);
  });
}
