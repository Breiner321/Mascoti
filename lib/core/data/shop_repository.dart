import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/cart_item.dart';
import '../domain/order.dart';
import '../domain/product.dart';

/// Error de la tienda con el mensaje para mostrar.
@immutable
class ShopFailure implements Exception {
  const ShopFailure(this.message, {this.canRetry = false, this.code});

  final String message;
  final bool canRetry;

  /// Código del servidor (`failed-precondition`, `resource-exhausted`…), si
  /// lo hay.
  final String? code;

  static const network = ShopFailure('No se pudo conectar. Verifica tu conexión', canRetry: true);
  static const notConfigured =
      ShopFailure('La tienda no está disponible en esta versión de la app');

  @override
  String toString() => 'ShopFailure($message)';
}

/// El carrito tiene productos de otra clínica. La pantalla pregunta "Tu
/// carrito tiene productos de otra clínica. ¿Vaciarlo?" y, si el dueño
/// acepta, vuelve a llamar a `addToCart(..., replaceOtherClinic: true)`.
@immutable
class CartFromOtherClinic extends ShopFailure {
  const CartFromOtherClinic()
      : super('Tu carrito tiene productos de otra clínica. ¿Vaciarlo?');
}

/// Lo que devuelve `crear-pedido`: abrir [checkoutUrl] (Web Checkout de
/// Wompi) en un WebView y cerrarlo cuando navegue a [redirectUrl]
/// (ver [ShopRepository.isCheckoutReturn]). El estado real del pago llega
/// por el webhook: la pantalla escucha `watchOrder(orderId)`.
@immutable
class CheckoutSession {
  const CheckoutSession({
    required this.orderId,
    required this.checkoutUrl,
    required this.redirectUrl,
    required this.total,
    required this.expiraEn,
  });

  factory CheckoutSession.fromMap(Map<String, dynamic> map) => CheckoutSession(
        orderId: map['orderId'] as String,
        checkoutUrl: map['checkoutUrl'] as String,
        redirectUrl: map['redirectUrl'] as String? ?? '',
        total: (map['total'] as num?)?.toInt() ?? 0,
        expiraEn: DateTime.tryParse(map['expiraEn'] as String? ?? '') ??
            DateTime.now().add(const Duration(minutes: OrderLimits.reservaMin)),
      );

  final String orderId;
  final String checkoutUrl;
  final String redirectUrl;

  /// Total en pesos calculado por el servidor.
  final int total;
  final DateTime expiraEn;
}

/// Tienda (RF-07, RF-12), compartido por el inventario de la clínica y la
/// tienda del dueño.
///
/// - Productos: la clínica los escribe directo (firestore.rules valida
///   nombre, precio, stock y que `agotado` ⇔ `stock == 0`); `stockReservado`
///   solo lo cambia el servidor.
/// - Carrito: `users/{uid}/cart/{productId}`, directo (solo su dueño).
/// - Pedidos: solo lectura. Crear y cambiar de estado van por las Edge
///   Functions `crear-pedido` y `actualizar-pedido`; el pago lo confirma
///   únicamente el webhook de Wompi. La app nunca calcula el total cobrado
///   ni marca un pedido como pagado.
class ShopRepository {
  ShopRepository({FirebaseFirestore? firestore, FunctionsClient? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions;

  final FirebaseFirestore _firestore;

  /// null = Supabase no está configurado (falta env/dev.json).
  final FunctionsClient? _functions;

  static const createOrderFunction = 'crear-pedido';
  static const updateOrderFunction = 'actualizar-pedido';
  static const _timeout = Duration(seconds: 30);

  /// Productos que ve un dueño.
  static final _visibleStatuses = [ProductStatus.activo.value, ProductStatus.agotado.value];

  CollectionReference<Map<String, dynamic>> _products(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).collection('products');

  CollectionReference<Map<String, dynamic>> _cart(String uid) =>
      _firestore.collection('users').doc(uid).collection('cart');

  CollectionReference<Map<String, dynamic>> get _orders => _firestore.collection('orders');

  static List<Product> _productList(QuerySnapshot<Map<String, dynamic>> snap) =>
      [for (final d in snap.docs) Product.fromMap(d.id, d.data())]
        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

  static List<ShopOrder> _orderList(QuerySnapshot<Map<String, dynamic>> snap) =>
      [for (final d in snap.docs) ShopOrder.fromMap(d.id, d.data())];

  // ---------------------------------------------------------------------------
  // Productos
  // ---------------------------------------------------------------------------

  /// Productos de una clínica por nombre. Para el dueño ([forClinic] false)
  /// solo activos y agotados; la clínica ve también los inactivos.
  Stream<List<Product>> watchClinicProducts(String clinicId, {bool forClinic = false}) {
    Query<Map<String, dynamic>> query = _products(clinicId);
    if (!forClinic) query = query.where('estado', whereIn: _visibleStatuses);
    return query.snapshots().map(_productList);
  }

  /// Catálogo general (RF-12 paso 1): productos activos y agotados de todas
  /// las clínicas (consulta de grupo `products`), por nombre.
  Stream<List<Product>> watchCatalog({int limit = 200}) => _firestore
      .collectionGroup('products')
      .where('estado', whereIn: _visibleStatuses)
      .limit(limit)
      .snapshots()
      .map(_productList);

  /// Un producto, o null si no existe (o un dueño no lo puede ver).
  Stream<Product?> watchProduct(String clinicId, String productId) =>
      _products(clinicId).doc(productId).snapshots().map(
            (d) => d.exists ? Product.fromMap(d.id, d.data()!) : null,
          );

  /// Id para un producto nuevo: se usa para la ruta de la foto
  /// (`{uid}/{productId}.jpg` en el bucket `productos`) antes de crearlo.
  String newProductId(String clinicId) => _products(clinicId).doc().id;

  /// Crea el producto ([product.id] de [newProductId]) con `stockReservado`
  /// en 0 y `createdAt` del servidor.
  Future<void> createProduct(Product product) => _products(product.clinicId).doc(product.id).set({
        ...product.copyWith(stock: product.stock).toMap(),
        'stockReservado': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Guarda los cambios de la clínica. El estado se ajusta al stock (salvo
  /// inactivo) para cumplir `agotado` ⇔ `stock == 0`.
  Future<void> updateProduct(Product product) {
    final normalized = product.estado == ProductStatus.inactivo
        ? product
        : product.copyWith(estado: ProductStatus.forStock(product.stock));
    return _products(product.clinicId).doc(product.id).update({
      ...normalized.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Botones +/- del stock (RF-07 paso 9), en una transacción: no pisa una
  /// venta que el servidor confirme al mismo tiempo. 0 → agotado.
  Future<void> adjustStock(String clinicId, String productId, int delta) =>
      _firestore.runTransaction((tx) async {
        final ref = _products(clinicId).doc(productId);
        final snap = await tx.get(ref);
        if (!snap.exists) throw const ShopFailure('No encontramos el producto.');
        final product = Product.fromMap(snap.id, snap.data()!);
        final stock = product.stock + delta;
        if (stock < 0) throw const ShopFailure('El stock no puede ser negativo');
        final updated = product.copyWith(stock: stock);
        tx.update(ref, {
          'stock': updated.stock,
          'estado': updated.estado.value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Borrado lógico (RF-07): el producto sale de la tienda del dueño.
  Future<void> deactivateProduct(String clinicId, String productId) =>
      _products(clinicId).doc(productId).update({
        'estado': ProductStatus.inactivo.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Vuelve a publicar un producto inactivo (activo o agotado según stock).
  Future<void> reactivateProduct(Product product) =>
      _products(product.clinicId).doc(product.id).update({
        'estado': ProductStatus.forStock(product.stock).value,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ---------------------------------------------------------------------------
  // Carrito
  // ---------------------------------------------------------------------------

  /// Carrito de [uid], el más antiguo primero.
  Stream<List<CartItem>> watchCart(String uid) => _cart(uid).snapshots().map((snap) {
        final items = [for (final d in snap.docs) CartItem.fromMap(d.id, d.data())];
        items.sort((a, b) => (a.addedAt ?? DateTime(9999)).compareTo(b.addedAt ?? DateTime(9999)));
        return items;
      });

  /// Agrega [cantidad] unidades de [product] (RF-12 paso 2). No deja pasar
  /// de lo disponible en tiempo real (paso 3) ni de 99.
  ///
  /// Un carrito solo tiene productos de UNA clínica: si ya tiene de otra,
  /// lanza [CartFromOtherClinic]; con [replaceOtherClinic] vacía el
  /// carrito y agrega el producto (en un solo lote).
  Future<void> addToCart(
    String uid,
    Product product,
    int cantidad, {
    bool replaceOtherClinic = false,
  }) async {
    if (cantidad <= 0) throw const ShopFailure('Elige al menos una unidad.');
    if (product.estado != ProductStatus.activo || product.available == 0) {
      throw ShopFailure('${product.nombre} está agotado.');
    }
    final current = await _cart(uid).get();
    final others = current.docs.where((d) => d.data()['clinicId'] != product.clinicId).toList();
    if (others.isNotEmpty && !replaceOtherClinic) throw const CartFromOtherClinic();
    final sameClinic = current.docs.length - others.length;

    final existing = current.docs.where((d) => d.id == product.id).firstOrNull;
    final inCart = existing == null ? 0 : CartItem.fromMap(existing.id, existing.data()).cantidad;
    if (existing == null && sameClinic >= CartLimits.maxItems) {
      throw const ShopFailure(
        'Tu carrito ya tiene ${CartLimits.maxItems} productos distintos.',
      );
    }
    final total = inCart + cantidad;
    _checkQuantity(product, total);

    final batch = _firestore.batch();
    for (final d in others) {
      batch.delete(d.reference);
    }
    batch.set(_cart(uid).doc(product.id), {
      ...CartItem(
        productId: product.id,
        clinicId: product.clinicId,
        nombre: product.nombre,
        precio: product.precio,
        cantidad: total,
      ).toMap(),
      'addedAt': existing?.data()['addedAt'] ?? FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Cambia la cantidad (0 = quitar). Con [product] valida contra lo
  /// disponible y actualiza el precio de referencia.
  Future<void> setCartQuantity(String uid, String productId, int cantidad, {Product? product}) {
    if (cantidad <= 0) return removeFromCart(uid, productId);
    if (product != null) _checkQuantity(product, cantidad);
    return _cart(uid).doc(productId).update({
      'cantidad': cantidad,
      if (product != null) 'precio': product.precio,
      if (product != null) 'nombre': product.nombre,
    });
  }

  Future<void> removeFromCart(String uid, String productId) =>
      _cart(uid).doc(productId).delete();

  /// Vacía el carrito (el servidor también lo vacía cuando el pago se aprueba).
  Future<void> clearCart(String uid) async {
    final batch = _firestore.batch();
    for (final d in (await _cart(uid).get()).docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  static void _checkQuantity(Product product, int cantidad) {
    if (cantidad > CartLimits.maxCantidad) {
      throw const ShopFailure('Puedes llevar hasta ${CartLimits.maxCantidad} unidades.');
    }
    if (cantidad > product.available) {
      final n = product.available;
      throw ShopFailure(
        'Solo ${n == 1 ? 'queda 1 unidad' : 'quedan $n unidades'} de ${product.nombre}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Pedidos (lectura)
  // ---------------------------------------------------------------------------

  /// "Mis pedidos" del dueño, el más reciente primero.
  Stream<List<ShopOrder>> watchOwnerOrders(String ownerUid) => _orders
      .where('ownerUid', isEqualTo: ownerUid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(_orderList);

  /// Pedidos de la clínica, el más reciente primero. Solo los ya pagados
  /// (las reglas no le dejan leer los pendientes de pago, rechazados o
  /// expirados); con [estados] se filtra más (p. ej. solo `pagado`).
  Stream<List<ShopOrder>> watchClinicOrders(String clinicId, {List<OrderStatus>? estados}) {
    final allowed = (estados ?? OrderStatus.visibleToClinic)
        .where(OrderStatus.visibleToClinic.contains)
        .map((s) => s.value)
        .toList();
    if (allowed.isEmpty) return Stream.value(const []);
    return _orders
        .where('clinicId', isEqualTo: clinicId)
        .where('estado', whereIn: allowed)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_orderList);
  }

  /// Un pedido (detalle y espera del pago), o null si no existe.
  Stream<ShopOrder?> watchOrder(String orderId) => _orders.doc(orderId).snapshots().map(
        (d) => d.exists ? ShopOrder.fromMap(d.id, d.data()!) : null,
      );

  // ---------------------------------------------------------------------------
  // Acciones (Edge Functions)
  // ---------------------------------------------------------------------------

  /// "Confirmar compra" (RF-12 paso 6): el servidor lee el carrito y los
  /// precios, aparta el stock 15 min y devuelve el Web Checkout de Wompi.
  /// Si falta stock lanza [ShopFailure] con el detalle ("Solo quedan 2
  /// unidades de X").
  Future<CheckoutSession> createOrder({
    required String clinicId,
    required OrderDelivery delivery,
  }) async {
    final error = delivery.validate();
    if (error != null) throw ShopFailure(error);
    final data = await _invoke(createOrderFunction, {
      'clinicId': clinicId,
      'entrega': delivery.toMap(),
    });
    return CheckoutSession.fromMap(data);
  }

  /// La clínica cambia el estado del pedido. Cancelar exige [motivo].
  Future<void> updateOrderStatus(String orderId, OrderStatus estado, {String? motivo}) async {
    if (!estado.isSetByClinic) throw const ShopFailure('Estado no válido.');
    final reason = motivo?.trim() ?? '';
    if (estado == OrderStatus.cancelado && reason.isEmpty) {
      throw const ShopFailure('Indica el motivo de la cancelación.');
    }
    if (reason.length > OrderLimits.maxMotivo) {
      throw const ShopFailure('El motivo no puede superar ${OrderLimits.maxMotivo} caracteres.');
    }
    await _invoke(updateOrderFunction, {
      'orderId': orderId,
      'estado': estado.value,
      if (reason.isNotEmpty) 'motivo': reason,
    });
  }

  /// true si el WebView del checkout llegó a la URL de regreso: se cierra y
  /// la pantalla muestra el estado del pedido (que confirma el webhook).
  static bool isCheckoutReturn(String url, String redirectUrl) =>
      redirectUrl.isNotEmpty && url.startsWith(redirectUrl);

  Future<Map<String, dynamic>> _invoke(String function, Map<String, dynamic> body) async {
    final functions = _functions;
    if (functions == null) throw ShopFailure.notConfigured;
    try {
      final response = await functions.invoke(function, body: body).timeout(_timeout);
      return Map<String, dynamic>.from(response.data as Map);
    } on TimeoutException {
      throw ShopFailure.network;
    } on SocketException {
      throw ShopFailure.network;
    } on http.ClientException {
      throw ShopFailure.network;
    } on FunctionException catch (e) {
      final error = e.details is Map ? (e.details as Map)['error'] : null;
      final code = error is Map ? error['code'] as String? : null;
      final message = error is Map ? error['message'] as String? : null;
      throw ShopFailure(
        message ?? 'No se pudo completar la acción. Intenta de nuevo.',
        canRetry: e.status >= 500 || code == 'aborted',
        code: code,
      );
    }
  }
}
