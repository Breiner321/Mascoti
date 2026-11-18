import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Límites del carrito (iguales a firestore.rules y a `crear-pedido`).
abstract final class CartLimits {
  /// Unidades máximas de un producto en el carrito.
  static const maxCantidad = 99;

  /// Productos distintos en un pedido.
  static const maxItems = 30;
}

/// Documento `users/{uid}/cart/{productId}` (RF-12). Un carrito solo tiene
/// productos de UNA clínica (lo controla `ShopRepository.addToCart`; el
/// servidor lo vuelve a verificar al crear el pedido).
///
/// [precio] y [nombre] son solo de referencia para mostrar el carrito sin
/// esperar al catálogo: el total lo calcula el servidor con el precio real.
@immutable
class CartItem {
  const CartItem({
    required this.productId,
    required this.clinicId,
    required this.nombre,
    required this.precio,
    required this.cantidad,
    this.addedAt,
  });

  factory CartItem.fromMap(String productId, Map<String, dynamic> map) => CartItem(
        productId: productId,
        clinicId: map['clinicId'] as String? ?? '',
        nombre: map['nombre'] as String? ?? '',
        precio: (map['precio'] as num?)?.toInt() ?? 0,
        cantidad: (map['cantidad'] as num?)?.toInt() ?? 0,
        addedAt: (map['addedAt'] as Timestamp?)?.toDate(),
      );

  final String productId;
  final String clinicId;
  final String nombre;

  /// Precio de referencia en pesos (el del catálogo al agregarlo).
  final int precio;
  final int cantidad;
  final DateTime? addedAt;

  /// Subtotal de referencia (precio × cantidad).
  int get subtotal => precio * cantidad;

  /// Sin `addedAt`: el repositorio lo pone con la hora del servidor.
  Map<String, dynamic> toMap() => {
        'clinicId': clinicId,
        'nombre': nombre,
        'precio': precio,
        'cantidad': cantidad,
      };

  CartItem copyWith({int? cantidad, int? precio, String? nombre}) => CartItem(
        productId: productId,
        clinicId: clinicId,
        nombre: nombre ?? this.nombre,
        precio: precio ?? this.precio,
        cantidad: cantidad ?? this.cantidad,
        addedAt: addedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is CartItem &&
      other.productId == productId &&
      other.clinicId == clinicId &&
      other.nombre == nombre &&
      other.precio == precio &&
      other.cantidad == cantidad &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(productId, clinicId, nombre, precio, cantidad, addedAt);
}

/// Total de referencia del carrito (el real lo calcula `crear-pedido`).
int cartReferenceTotal(Iterable<CartItem> items) =>
    items.fold(0, (total, item) => total + item.subtotal);

/// Unidades en el carrito (número del ícono del encabezado).
int cartUnits(Iterable<CartItem> items) =>
    items.fold(0, (total, item) => total + item.cantidad);
