import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/order.dart';

void main() {
  // Mismos casos que functions/test/estados_pedido.test.ts.
  final fixture =
      jsonDecode(File('test/fixtures/estados_pedido.json').readAsStringSync()) as Map<String, dynamic>;

  group('máquina de estados (test/fixtures/estados_pedido.json)', () {
    final valid = {
      for (final t in fixture['validas'] as List) (t as List).join('|'),
    };

    test('los estados y su valor en Firestore coinciden con el servidor', () {
      expect(OrderStatus.values.map((s) => s.value), fixture['estados']);
      expect(DeliveryType.values.map((d) => d.value), fixture['entregas']);
    });

    test('todas las combinaciones (de, a, entrega)', () {
      var checked = 0;
      for (final from in OrderStatus.values) {
        for (final to in OrderStatus.values) {
          for (final delivery in DeliveryType.values) {
            final key = '${from.value}|${to.value}|${delivery.value}';
            expect(from.canTransitionTo(to, delivery), valid.contains(key), reason: key);
            checked++;
          }
        }
      }
      expect(checked, 9 * 9 * 2);
    });

    test('estados finales y los que pone la clínica', () {
      expect(
        OrderStatus.values.where((s) => s.isFinal).map((s) => s.value),
        unorderedEquals(fixture['finales'] as List),
      );
      expect(
        OrderStatus.values.where((s) => s.isSetByClinic).map((s) => s.value),
        unorderedEquals(fixture['porLaClinica'] as List),
      );
    });

    test('listo es solo para recoger y enviado solo para domicilio', () {
      expect(OrderStatus.preparando.nextStates(DeliveryType.recoger),
          {OrderStatus.listo, OrderStatus.cancelado});
      expect(OrderStatus.preparando.nextStates(DeliveryType.domicilio),
          {OrderStatus.enviado, OrderStatus.cancelado});
    });

    test('la clínica ve solo pedidos pagados', () {
      expect(OrderStatus.visibleToClinic, isNot(contains(OrderStatus.pendientePago)));
      expect(OrderStatus.visibleToClinic, isNot(contains(OrderStatus.pagoRechazado)));
      expect(OrderStatus.visibleToClinic, isNot(contains(OrderStatus.expirado)));
    });
  });

  group('OrderDelivery', () {
    test('valida teléfono de 10 dígitos y dirección a domicilio', () {
      const pickup = OrderDelivery(tipo: DeliveryType.recoger, telefono: '3001234567');
      expect(pickup.validate(), isNull);
      expect(pickup.toMap(), {'tipo': 'recoger', 'telefono': '3001234567'});
      expect(const OrderDelivery(tipo: DeliveryType.recoger, telefono: '300123').validate(),
          'El teléfono debe tener 10 dígitos');
      expect(
        const OrderDelivery(tipo: DeliveryType.domicilio, telefono: '3001234567', direccion: 'Cl')
            .validate(),
        contains('dirección'),
      );
      const home = OrderDelivery(
        tipo: DeliveryType.domicilio,
        telefono: '3001234567',
        direccion: ' Calle 10 # 5-20 ',
      );
      expect(home.validate(), isNull);
      expect(home.toMap()['direccion'], 'Calle 10 # 5-20');
    });
  });

  group('ShopOrder', () {
    final doc = <String, dynamic>{
      'ownerUid': 'ana',
      'ownerNombre': 'Ana Pérez',
      'clinicId': 'c1',
      'clinicNombre': 'Vet Norte',
      'items': [
        {'productId': 'p1', 'nombre': 'Concentrado', 'precio': 45000, 'cantidad': 2},
        {'productId': 'p2', 'nombre': 'Collar', 'precio': 12000, 'cantidad': 1},
      ],
      'total': 102000,
      'entrega': {'tipo': 'domicilio', 'direccion': 'Calle 10', 'telefono': '3001234567'},
      'estado': 'pendiente_pago',
      'referenciaPago': 'MSC-o1',
      'expiraEn': Timestamp.fromDate(DateTime.utc(2026, 11, 18, 15, 15)),
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 18, 15)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 18, 15)),
    };

    test('fromMap lee los campos y toMap → fromMap conserva los datos', () {
      final order = ShopOrder.fromMap('o1', doc);
      expect(order.items, hasLength(2));
      expect(order.items.first.subtotal, 90000);
      expect(order.units, 3);
      expect(order.total, 102000);
      expect(order.estado, OrderStatus.pendientePago);
      expect(order.entrega.tipo, DeliveryType.domicilio);
      expect(order.pagoTardio, isFalse);
      expect(ShopOrder.fromMap('o1', order.toMap()), order);
    });

    test('campos opcionales del servidor', () {
      final order = ShopOrder.fromMap('o1', {
        ...doc,
        'estado': 'cancelado',
        'wompiTransactionId': '1234-1610641025-49201',
        'motivoCancelacion': 'Sin repartidor',
        'pagoTardio': true,
      });
      expect(order.estado, OrderStatus.cancelado);
      expect(order.wompiTransactionId, '1234-1610641025-49201');
      expect(order.motivoCancelacion, 'Sin repartidor');
      expect(order.pagoTardio, isTrue);
      expect(order.copyWith(estado: OrderStatus.entregado).estado, OrderStatus.entregado);
    });
  });
}
