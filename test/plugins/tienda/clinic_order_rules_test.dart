import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/order.dart';
import 'package:mascoti/plugins/tienda/domain/clinic_order_rules.dart';

ShopOrder order(OrderStatus estado, {DeliveryType tipo = DeliveryType.recoger, String id = 'o1'}) =>
    ShopOrder(
      id: id,
      ownerUid: 'u1',
      ownerNombre: 'Ana',
      clinicId: 'c1',
      clinicNombre: 'Vet',
      items: const [OrderItem(productId: 'p1', nombre: 'Collar', precio: 45000, cantidad: 1)],
      total: 45000,
      entrega: OrderDelivery(
        tipo: tipo,
        telefono: '3001234567',
        direccion: tipo == DeliveryType.domicilio ? 'Calle 1 # 2-3' : null,
      ),
      estado: estado,
      referenciaPago: 'MSC-$id',
    );

void main() {
  group('siguiente paso', () {
    test('sigue la máquina de estados', () {
      expect(ClinicOrderRules.nextAction(order(OrderStatus.pagado)),
          const OrderAction('Empezar a preparar', OrderStatus.preparando));
      expect(ClinicOrderRules.nextAction(order(OrderStatus.preparando)),
          const OrderAction('Listo para recoger', OrderStatus.listo));
      expect(
          ClinicOrderRules.nextAction(order(OrderStatus.preparando, tipo: DeliveryType.domicilio)),
          const OrderAction('Marcar como enviado', OrderStatus.enviado));
      expect(ClinicOrderRules.nextAction(order(OrderStatus.listo)),
          const OrderAction('Entregado', OrderStatus.entregado));
      expect(ClinicOrderRules.nextAction(order(OrderStatus.enviado, tipo: DeliveryType.domicilio)),
          const OrderAction('Entregado', OrderStatus.entregado));
    });

    test('sin paso siguiente en estados finales', () {
      expect(ClinicOrderRules.nextAction(order(OrderStatus.entregado)), isNull);
      expect(ClinicOrderRules.nextAction(order(OrderStatus.cancelado)), isNull);
    });
  });

  test('solo se cancela un pedido pagado o en preparación', () {
    expect(ClinicOrderRules.canCancel(order(OrderStatus.pagado)), isTrue);
    expect(ClinicOrderRules.canCancel(order(OrderStatus.preparando)), isTrue);
    expect(ClinicOrderRules.canCancel(order(OrderStatus.listo)), isFalse);
    expect(ClinicOrderRules.canCancel(order(OrderStatus.entregado)), isFalse);
    expect(ClinicOrderRules.canCancel(order(OrderStatus.cancelado)), isFalse);
  });

  test('el motivo de cancelación es obligatorio (máx. 300)', () {
    expect(ClinicOrderRules.validateReason(''), isNotNull);
    expect(ClinicOrderRules.validateReason('   '), isNotNull);
    expect(ClinicOrderRules.validateReason('x' * 301), isNotNull);
    expect(ClinicOrderRules.validateReason('Sin unidades'), isNull);
  });

  test('pestañas: por preparar, listos o enviados e historial', () {
    final all = [
      for (final (i, s) in OrderStatus.visibleToClinic.indexed)
        order(s,
            id: 'o$i',
            tipo: s == OrderStatus.enviado ? DeliveryType.domicilio : DeliveryType.recoger),
    ];
    List<OrderStatus> statuses(ClinicOrderTab t) => t.select(all).map((o) => o.estado).toList();
    expect(statuses(ClinicOrderTab.porPreparar), [OrderStatus.pagado, OrderStatus.preparando]);
    expect(statuses(ClinicOrderTab.listos), [OrderStatus.listo, OrderStatus.enviado]);
    expect(statuses(ClinicOrderTab.historial), [OrderStatus.entregado, OrderStatus.cancelado]);
  });
}
