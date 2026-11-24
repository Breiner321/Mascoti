import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/shop_repository.dart';
import 'package:mascoti/core/domain/cart_item.dart';
import 'package:mascoti/core/domain/order.dart';
import 'package:mascoti/core/domain/product.dart';
import 'package:mascoti/plugins/tienda/domain/cart_rules.dart';
import 'package:mascoti/plugins/tienda/domain/order_timeline.dart';

Product product({
  int precio = 45000,
  int stock = 5,
  int reservado = 0,
  ProductStatus estado = ProductStatus.activo,
}) =>
    Product(
      id: 'p1',
      clinicId: 'c1',
      nombre: 'Concentrado 2 kg',
      categoria: ProductCategory.alimento,
      precio: precio,
      stock: stock,
      stockReservado: reservado,
      fotoPath: '',
      estado: estado,
    );

CartItem item({int cantidad = 2, int precio = 45000}) => CartItem(
      productId: 'p1',
      clinicId: 'c1',
      nombre: 'Concentrado 2 kg',
      precio: precio,
      cantidad: cantidad,
    );

ShopOrder order(OrderStatus estado, {DeliveryType tipo = DeliveryType.recoger, DateTime? expiraEn}) =>
    ShopOrder(
      id: 'o1',
      ownerUid: 'ana',
      ownerNombre: 'Ana',
      clinicId: 'c1',
      clinicNombre: 'Vet Norte',
      items: const [],
      total: 90000,
      entrega: OrderDelivery(tipo: tipo, telefono: '3001234567', direccion: 'Calle 10'),
      estado: estado,
      referenciaPago: 'MSC-o1',
      expiraEn: expiraEn,
    );

void main() {
  group('avisos del carrito', () {
    test('sin cambios no hay avisos', () {
      expect(cartIssues(item(), product()), isEmpty);
    });

    test('agotado y no disponible bloquean el pago', () {
      expect(cartIssues(item(), product(stock: 0, estado: ProductStatus.agotado)).single, isA<SoldOut>());
      expect(cartIssues(item(), product(estado: ProductStatus.inactivo)).single, isA<ProductUnavailable>());
      expect(cartIssues(item(), null).single, isA<ProductUnavailable>());
      // Todo el stock apartado por otros pedidos = agotado para este dueño.
      expect(cartIssues(item(), product(stock: 3, reservado: 3)).single, isA<SoldOut>());
      expect(checkoutBlocked([cartIssues(item(), null)]), isTrue);
    });

    test('menos stock que en el carrito', () {
      final issue = cartIssues(item(cantidad: 4), product(stock: 2)).single as NotEnoughStock;
      expect(issue.available, 2);
      expect(issue.message, 'Solo quedan 2 unidades. Baja la cantidad.');
      expect(issue.blocksCheckout, isTrue);
    });

    test('cambio de precio avisa pero no bloquea', () {
      final issue = cartIssues(item(precio: 40000), product(precio: 45000)).single;
      expect(issue, isA<PriceChanged>());
      expect(issue.message, r'El precio cambió de $ 40.000 a $ 45.000.');
      expect(checkoutBlocked([[issue]]), isFalse);
    });
  });

  group('cantidades', () {
    test('máximo lo disponible y nunca más de 99', () {
      expect(maxQuantity(product(stock: 5, reservado: 2)), 3);
      expect(maxQuantity(product(stock: 500)), CartLimits.maxCantidad);
      expect(maxQuantity(product(stock: 0, estado: ProductStatus.agotado)), 0);
    });

    test('se ajusta entre 1 y el máximo', () {
      expect(clampQuantity(10, product(stock: 3)), 3);
      expect(clampQuantity(0, product(stock: 3)), 1);
      expect(clampQuantity(2, product(stock: 0, estado: ProductStatus.agotado)), 0);
    });
  });

  test('subtotal de referencia con los precios actuales si los hay', () {
    final items = [item(cantidad: 2, precio: 40000)];
    expect(referenceSubtotal(items), 80000);
    expect(referenceSubtotal(items, current: {'p1': product(precio: 45000)}), 90000);
  });

  test('pregunta de otra clínica', () {
    expect(otherClinicQuestion('Vet Sur'),
        'Tu carrito tiene productos de Vet Sur. ¿Vaciarlo y agregar este?');
    expect(otherClinicQuestion(''), contains('otra clínica'));
  });

  test('lo que lee TalkBack de una tarjeta', () {
    expect(productSemantics(product()), 'Concentrado 2 kg, 45.000 pesos');
    expect(productSemantics(product(stock: 0, estado: ProductStatus.agotado)),
        'Concentrado 2 kg, 45.000 pesos, agotado');
  });

  group('pedidos', () {
    final now = DateTime(2026, 11, 23, 10);

    test('activos: pendiente sin vencer y en curso', () {
      expect(isActiveOrder(order(OrderStatus.pendientePago, expiraEn: now.add(const Duration(minutes: 5))), now), isTrue);
      expect(isActiveOrder(order(OrderStatus.pendientePago, expiraEn: now.subtract(const Duration(minutes: 1))), now), isFalse);
      expect(isActiveOrder(order(OrderStatus.preparando), now), isTrue);
      expect(isActiveOrder(order(OrderStatus.entregado), now), isFalse);
      expect(isActiveOrder(order(OrderStatus.pagoRechazado), now), isFalse);
    });

    test('línea de tiempo según la entrega', () {
      expect(orderTimeline(order(OrderStatus.preparando)).map((s) => s.toString()),
          ['pagado:done', 'preparando:current', 'listo:pending', 'entregado:pending']);
      expect(orderTimeline(order(OrderStatus.enviado, tipo: DeliveryType.domicilio)).map((s) => s.toString()),
          ['pagado:done', 'preparando:done', 'enviado:current', 'entregado:pending']);
      expect(orderTimeline(order(OrderStatus.entregado)).every((s) => s.state == TimelineStepState.done), isTrue);
      expect(orderTimeline(order(OrderStatus.pendientePago)), isEmpty);
      expect(orderTimeline(order(OrderStatus.cancelado)), isEmpty);
    });
  });

  group('URL de regreso del Web Checkout', () {
    const redirect = 'https://x.supabase.co/functions/v1/webhook-wompi/retorno/o1';

    test('cierra el WebView al llegar a la URL de regreso', () {
      expect(ShopRepository.isCheckoutReturn('$redirect?id=123&env=test', redirect), isTrue);
      expect(ShopRepository.isCheckoutReturn(redirect, redirect), isTrue);
    });

    test('no se confunde con otras páginas ni sin URL', () {
      expect(ShopRepository.isCheckoutReturn('https://checkout.wompi.co/p/?public-key=x', redirect), isFalse);
      expect(ShopRepository.isCheckoutReturn(redirect, ''), isFalse);
    });
  });
}
