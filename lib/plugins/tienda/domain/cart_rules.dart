import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/domain/cart_item.dart';
import '../../../core/domain/order.dart';
import '../../../core/domain/product.dart';

/// Reglas del carrito del dueño (RF-12). El carrito guarda una copia del
/// precio al agregar; estos avisos comparan con el producto en tiempo real.
/// El total que se cobra lo calcula SIEMPRE el servidor (`crear-pedido`).

/// Problema de un producto del carrito frente a su estado actual.
@immutable
sealed class CartIssue {
  const CartIssue();

  /// Impide pagar hasta que se corrija.
  bool get blocksCheckout;

  String get message;
}

/// Ya no está a la venta (lo desactivaron o lo borraron).
class ProductUnavailable extends CartIssue {
  const ProductUnavailable();

  @override
  bool get blocksCheckout => true;

  @override
  String get message =>
      'Este producto ya no está disponible. Quítalo del carrito.';
}

class SoldOut extends CartIssue {
  const SoldOut();

  @override
  bool get blocksCheckout => true;

  @override
  String get message => 'Se agotó. Quítalo del carrito para continuar.';
}

/// Quedan menos unidades que las del carrito.
class NotEnoughStock extends CartIssue {
  const NotEnoughStock(this.available);

  final int available;

  @override
  bool get blocksCheckout => true;

  @override
  String get message => available == 1
      ? 'Solo queda 1 unidad. Baja la cantidad.'
      : 'Solo quedan $available unidades. Baja la cantidad.';
}

/// El precio cambió desde que se agregó (no bloquea: el servidor cobra el
/// precio actual).
class PriceChanged extends CartIssue {
  const PriceChanged({required this.before, required this.now});

  final int before;
  final int now;

  @override
  bool get blocksCheckout => false;

  @override
  String get message => 'El precio cambió de ${_cop(before)} a ${_cop(now)}.';

  static String _cop(int v) {
    final digits = v.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '\$ $buffer';
  }
}

/// Problemas de [item] frente a [product] (null = no existe). El más grave
/// primero: no disponible, agotado, poco stock, cambio de precio.
List<CartIssue> cartIssues(CartItem item, Product? product) {
  if (product == null || product.estado == ProductStatus.inactivo) {
    return const [ProductUnavailable()];
  }
  final issues = <CartIssue>[];
  if (product.estado == ProductStatus.agotado || product.available == 0) {
    issues.add(const SoldOut());
  } else if (item.cantidad > product.available) {
    issues.add(NotEnoughStock(product.available));
  }
  if (product.precio != item.precio) {
    issues.add(PriceChanged(before: item.precio, now: product.precio));
  }
  return issues;
}

/// Máximo que se puede elegir de [product]: lo disponible, sin pasar de 99.
int maxQuantity(Product product) =>
    max(0, min(product.available, CartLimits.maxCantidad));

/// Cantidad válida entre 1 y [maxQuantity] (0 si está agotado).
int clampQuantity(int cantidad, Product product) {
  final top = maxQuantity(product);
  if (top == 0) return 0;
  return cantidad.clamp(1, top);
}

/// Subtotal de REFERENCIA (precios del carrito, o los actuales si los hay).
int referenceSubtotal(List<CartItem> items,
        {Map<String, Product> current = const {}}) =>
    items.fold(
        0,
        (sum, i) =>
            sum + (current[i.productId]?.precio ?? i.precio) * i.cantidad);

/// true si algún producto impide pagar.
bool checkoutBlocked(Iterable<List<CartIssue>> issues) =>
    issues.any((list) => list.any((i) => i.blocksCheckout));

/// Lo que se agrega a un carrito que tiene productos de otra clínica.
String otherClinicQuestion(String clinicNombre) =>
    'Tu carrito tiene productos de ${clinicNombre.isEmpty ? 'otra clínica' : clinicNombre}. '
    '¿Vaciarlo y agregar este?';

/// "Concentrado 2 kg, 45.000 pesos, agotado": lo que lee TalkBack de una
/// tarjeta del catálogo.
String productSemantics(Product product) {
  final price = PriceChanged._cop(product.precio).replaceFirst('\$ ', '');
  final soldOut =
      product.estado == ProductStatus.agotado || product.available == 0;
  return '${product.nombre}, $price pesos${soldOut ? ', agotado' : ''}';
}

/// Pedidos "Activos": esperando pago (sin vencer) o en curso.
bool isActiveOrder(ShopOrder order, DateTime now) => switch (order.estado) {
      OrderStatus.pendientePago =>
        order.expiraEn == null || order.expiraEn!.isAfter(now),
      OrderStatus.pagado ||
      OrderStatus.preparando ||
      OrderStatus.listo ||
      OrderStatus.enviado =>
        true,
      _ => false,
    };
