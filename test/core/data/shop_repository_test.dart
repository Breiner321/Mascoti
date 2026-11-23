import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/shop_repository.dart';
import 'package:mascoti/core/domain/order.dart';
import 'package:mascoti/core/domain/product.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockFunctions extends Mock implements FunctionsClient {}

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockFunctions functions;
  late ShopRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    functions = _MockFunctions();
    repository = ShopRepository(firestore: firestore, functions: functions);
  });

  Product product(
    String id, {
    String clinicId = 'c1',
    String nombre = 'Concentrado',
    int precio = 45000,
    int stock = 5,
    int stockReservado = 0,
    ProductStatus? estado,
  }) =>
      Product(
        id: id,
        clinicId: clinicId,
        nombre: nombre,
        categoria: ProductCategory.alimento,
        precio: precio,
        stock: stock,
        stockReservado: stockReservado,
        fotoPath: 'vet/$id.jpg',
        estado: estado ?? ProductStatus.forStock(stock),
      );

  Future<void> seedProduct(Product p) => firestore
      .doc('clinics/${p.clinicId}/products/${p.id}')
      .set({...p.toMap(), 'stockReservado': p.stockReservado});

  Future<Map<String, dynamic>?> cartDoc(String productId) async =>
      (await firestore.doc('users/ana/cart/$productId').get()).data();

  group('productos', () {
    test('el dueño ve activos y agotados por nombre; la clínica también inactivos', () async {
      await seedProduct(product('p1', nombre: 'Collar'));
      await seedProduct(product('p2', nombre: 'Arena', stock: 0));
      await seedProduct(product('p3', nombre: 'Viejo', estado: ProductStatus.inactivo));
      await seedProduct(product('q1', clinicId: 'c2', nombre: 'Pelota'));

      final owner = await repository.watchClinicProducts('c1').first;
      expect(owner.map((p) => p.nombre), ['Arena', 'Collar']);
      final clinic = await repository.watchClinicProducts('c1', forClinic: true).first;
      expect(clinic.map((p) => p.id), ['p2', 'p1', 'p3']);
      final catalog = await repository.watchCatalog().first;
      expect(catalog.map((p) => p.nombre), ['Arena', 'Collar', 'Pelota']);
    });

    test('crear guarda stockReservado 0 y createdAt; el estado sigue al stock', () async {
      final id = repository.newProductId('c1');
      await repository.createProduct(product(id, stock: 0, estado: ProductStatus.activo));
      final data = (await firestore.doc('clinics/c1/products/$id').get()).data()!;
      expect(data['stockReservado'], 0);
      expect(data['estado'], 'agotado');
      expect(data['createdAt'], isA<Timestamp>());
    });

    test('botones +/- del stock: llegar a 0 lo agota y subir lo reactiva', () async {
      await seedProduct(product('p1', stock: 1));
      await repository.adjustStock('c1', 'p1', -1);
      var data = (await firestore.doc('clinics/c1/products/p1').get()).data()!;
      expect(data['stock'], 0);
      expect(data['estado'], 'agotado');
      await repository.adjustStock('c1', 'p1', 3);
      data = (await firestore.doc('clinics/c1/products/p1').get()).data()!;
      expect(data['estado'], 'activo');
      expect(() => repository.adjustStock('c1', 'p1', -9), throwsA(isA<ShopFailure>()));
    });

    test('desactivar y reactivar (soft delete)', () async {
      final p = product('p1', stock: 0);
      await seedProduct(p);
      await repository.deactivateProduct('c1', 'p1');
      expect((await firestore.doc('clinics/c1/products/p1').get()).data()!['estado'], 'inactivo');
      await repository.reactivateProduct(p);
      expect((await firestore.doc('clinics/c1/products/p1').get()).data()!['estado'], 'agotado');
    });
  });

  group('carrito', () {
    test('agregar suma cantidades y guarda el precio de referencia', () async {
      final p = product('p1');
      await repository.addToCart('ana', p, 2);
      await repository.addToCart('ana', p, 1);
      final data = (await cartDoc('p1'))!;
      expect(data['cantidad'], 3);
      expect(data['precio'], 45000);
      expect(data['clinicId'], 'c1');
      final cart = await repository.watchCart('ana').first;
      expect(cart.single.subtotal, 135000);
    });

    test('no deja pasar de lo disponible (stock - reservado)', () async {
      final p = product('p1', stock: 3, stockReservado: 1);
      await expectLater(
        repository.addToCart('ana', p, 3),
        throwsA(isA<ShopFailure>()
            .having((e) => e.message, 'message', 'Solo quedan 2 unidades de Concentrado')),
      );
      await expectLater(
        repository.addToCart('ana', product('p2', stock: 0), 1),
        throwsA(isA<ShopFailure>()),
      );
    });

    test('un carrito, una clínica: pregunta y luego reemplaza', () async {
      await repository.addToCart('ana', product('p1'), 1);
      final other = product('q1', clinicId: 'c2', nombre: 'Pelota');
      await expectLater(
        repository.addToCart('ana', other, 1),
        throwsA(isA<CartFromOtherClinic>().having(
          (e) => e.message,
          'message',
          'Tu carrito tiene productos de otra clínica. ¿Vaciarlo?',
        )),
      );
      await repository.addToCart('ana', other, 1, replaceOtherClinic: true);
      expect(await cartDoc('p1'), isNull);
      expect((await cartDoc('q1'))!['clinicId'], 'c2');
    });

    test('cambiar cantidad, quitar con 0 y vaciar', () async {
      final p = product('p1');
      await repository.addToCart('ana', p, 1);
      await repository.addToCart('ana', product('p2'), 1);
      await repository.setCartQuantity('ana', 'p1', 4, product: p);
      expect((await cartDoc('p1'))!['cantidad'], 4);
      expect(() => repository.setCartQuantity('ana', 'p1', 6, product: p),
          throwsA(isA<ShopFailure>()));
      await repository.setCartQuantity('ana', 'p1', 0);
      expect(await cartDoc('p1'), isNull);
      await repository.clearCart('ana');
      expect(await repository.watchCart('ana').first, isEmpty);
    });
  });

  group('pedidos', () {
    Future<void> seedOrder(String id,
            {String owner = 'ana',
            String clinic = 'c1',
            required String estado,
            required int day}) =>
        firestore.doc('orders/$id').set({
          'ownerUid': owner,
          'clinicId': clinic,
          'estado': estado,
          'total': 1000,
          'items': [],
          'entrega': {'tipo': 'recoger', 'telefono': '3001234567'},
          'referenciaPago': 'MSC-$id',
          'createdAt': Timestamp.fromDate(DateTime(2026, 11, day)),
        });

    test('mis pedidos (el más reciente primero) y los pagados de la clínica', () async {
      await seedOrder('o1', estado: 'pagado', day: 10);
      await seedOrder('o2', estado: 'pendiente_pago', day: 12);
      await seedOrder('o3', owner: 'beto', estado: 'preparando', day: 11);
      await seedOrder('o4', clinic: 'c2', estado: 'pagado', day: 9);

      final mine = await repository.watchOwnerOrders('ana').first;
      expect(mine.map((o) => o.id), ['o2', 'o1', 'o4']);
      final clinic = await repository.watchClinicOrders('c1').first;
      expect(clinic.map((o) => o.id), ['o3', 'o1']);
      final onlyPaid =
          await repository.watchClinicOrders('c1', estados: [OrderStatus.pagado]).first;
      expect(onlyPaid.map((o) => o.id), ['o1']);
      expect((await repository.watchOrder('o2').first)!.estado, OrderStatus.pendientePago);
      expect(await repository.watchOrder('nada').first, isNull);
    });
  });

  group('Edge Functions', () {
    const delivery = OrderDelivery(tipo: DeliveryType.recoger, telefono: '3001234567');

    void answer(String function, Map<String, dynamic> data) {
      when(() => functions.invoke(function, body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(data: data, status: 200));
    }

    void failWith(String function, int status, String code, String message) {
      when(() => functions.invoke(function, body: any(named: 'body'))).thenThrow(
        FunctionException(status: status, details: {
          'error': {'code': code, 'message': message},
        }),
      );
    }

    Map<String, dynamic> sentBody(String function) =>
        verify(() => functions.invoke(function, body: captureAny(named: 'body'))).captured.single
            as Map<String, dynamic>;

    test('crear pedido envía clínica y entrega, y devuelve el checkout', () async {
      answer('crear-pedido', {
        'orderId': 'o1',
        'checkoutUrl': 'https://checkout.wompi.co/p/?reference=MSC-o1',
        'redirectUrl': 'https://mascoti.app/pago',
        'total': 90000,
        'expiraEn': '2026-11-18T15:15:00.000Z',
      });
      final session = await repository.createOrder(clinicId: 'c1', delivery: delivery);
      expect(session.orderId, 'o1');
      expect(session.total, 90000);
      expect(session.expiraEn, DateTime.utc(2026, 11, 18, 15, 15));
      expect(sentBody('crear-pedido'), {
        'clinicId': 'c1',
        'entrega': {'tipo': 'recoger', 'telefono': '3001234567'},
      });
      // Respuesta sin `pasarela` (servidor anterior): era Wompi.
      expect(session.gateway, PaymentGateway.wompi);
      expect(session.isSimulated, isFalse);
      expect(
          ShopRepository.isCheckoutReturn(
              'https://mascoti.app/pago?id=1-2-3', session.redirectUrl!),
          isTrue);
      expect(ShopRepository.isCheckoutReturn('https://checkout.wompi.co/p/', session.redirectUrl!),
          isFalse);
    });

    test('con pagos simulados no hay página de pago', () async {
      answer('crear-pedido', {
        'orderId': 'o2',
        'pasarela': 'simulada',
        'checkoutUrl': null,
        'redirectUrl': null,
        'total': 45000,
        'expiraEn': '2026-11-18T15:15:00.000Z',
      });
      final session = await repository.createOrder(clinicId: 'c1', delivery: delivery);
      expect(session.isSimulated, isTrue);
      expect(session.checkoutUrl, isNull);
      expect(session.total, 45000);
    });

    test('pago simulado: aprobado o rechazado, y errores del servidor', () async {
      answer('pagar-pedido-simulado', {'resultado': 'pagado', 'orderId': 'o1'});
      await repository.paySimulated('o1');
      expect(sentBody('pagar-pedido-simulado'), {'orderId': 'o1', 'resultado': 'aprobado'});

      await repository.paySimulated('o1', approve: false);
      expect(sentBody('pagar-pedido-simulado'), {'orderId': 'o1', 'resultado': 'rechazado'});

      failWith('pagar-pedido-simulado', 412, 'failed-precondition',
          'El tiempo para pagar este pedido terminó. Vuelve a confirmar la compra.');
      await expectLater(
        repository.paySimulated('o1'),
        throwsA(isA<ShopFailure>().having((e) => e.message, 'message',
            'El tiempo para pagar este pedido terminó. Vuelve a confirmar la compra.')),
      );
    });

    test('la entrega inválida no llega al servidor', () async {
      await expectLater(
        repository.createOrder(
          clinicId: 'c1',
          delivery: const OrderDelivery(tipo: DeliveryType.domicilio, telefono: '3001234567'),
        ),
        throwsA(isA<ShopFailure>()),
      );
      verifyNever(() => functions.invoke(any(), body: any(named: 'body')));
    });

    test('traduce los errores del servidor (stock) y de red', () async {
      failWith('crear-pedido', 412, 'failed-precondition', 'Solo quedan 2 unidades de Concentrado');
      await expectLater(
        repository.createOrder(clinicId: 'c1', delivery: delivery),
        throwsA(isA<ShopFailure>()
            .having((e) => e.message, 'message', 'Solo quedan 2 unidades de Concentrado')
            .having((e) => e.code, 'code', 'failed-precondition')
            .having((e) => e.canRetry, 'canRetry', isFalse)),
      );
      when(() => functions.invoke('crear-pedido', body: any(named: 'body')))
          .thenThrow(const SocketException('sin red'));
      await expectLater(
        repository.createOrder(clinicId: 'c1', delivery: delivery),
        throwsA(same(ShopFailure.network)),
      );
    });

    test('sin Supabase configurado', () async {
      final offline = ShopRepository(firestore: firestore);
      await expectLater(
        offline.createOrder(clinicId: 'c1', delivery: delivery),
        throwsA(same(ShopFailure.notConfigured)),
      );
    });

    test('actualizar estado: cancelar exige motivo; estados del servidor no se envían', () async {
      answer('actualizar-pedido', {'ok': true});
      await repository.updateOrderStatus('o1', OrderStatus.preparando);
      expect(sentBody('actualizar-pedido'), {'orderId': 'o1', 'estado': 'preparando'});

      await expectLater(
        repository.updateOrderStatus('o1', OrderStatus.cancelado),
        throwsA(isA<ShopFailure>()
            .having((e) => e.message, 'message', 'Indica el motivo de la cancelación.')),
      );
      await expectLater(
        repository.updateOrderStatus('o1', OrderStatus.pagado),
        throwsA(isA<ShopFailure>()),
      );
      await repository.updateOrderStatus('o1', OrderStatus.cancelado, motivo: ' Sin stock ');
      expect(sentBody('actualizar-pedido'),
          {'orderId': 'o1', 'estado': 'cancelado', 'motivo': 'Sin stock'});
    });
  });
}
