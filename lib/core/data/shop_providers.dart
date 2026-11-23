import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../domain/cart_item.dart';
import '../domain/order.dart';
import '../domain/product.dart';
import '../supabase/supabase_providers.dart';
import 'shop_repository.dart';

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository(functions: ref.watch(supabaseClientProvider)?.functions);
});

/// Productos de una clínica que ve el dueño (activos y agotados).
final clinicProductsProvider = StreamProvider.autoDispose.family<List<Product>, String>(
  (ref, clinicId) => ref.watch(shopRepositoryProvider).watchClinicProducts(clinicId),
  retry: (_, __) => null,
);

/// Inventario completo de la clínica [clinicId] (incluye inactivos).
final inventoryProvider = StreamProvider.autoDispose.family<List<Product>, String>(
  (ref, clinicId) =>
      ref.watch(shopRepositoryProvider).watchClinicProducts(clinicId, forClinic: true),
  retry: (_, __) => null,
);

/// Catálogo general de la tienda del dueño.
final catalogProvider = StreamProvider.autoDispose<List<Product>>(
  (ref) => ref.watch(shopRepositoryProvider).watchCatalog(),
  retry: (_, __) => null,
);

/// Un producto: `productProvider((clinicId: 'c1', productId: 'p1'))`.
final productProvider = StreamProvider.autoDispose
    .family<Product?, ({String clinicId, String productId})>(
  (ref, q) => ref.watch(shopRepositoryProvider).watchProduct(q.clinicId, q.productId),
  retry: (_, __) => null,
);

/// Carrito del usuario con sesión (vacío sin sesión).
final cartProvider = StreamProvider.autoDispose<List<CartItem>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(shopRepositoryProvider).watchCart(uid);
}, retry: (_, __) => null);

/// Unidades en el carrito: número del ícono del encabezado (0 sin conexión
/// o con error).
final cartCountProvider = Provider.autoDispose<int>(
  (ref) => cartUnits(ref.watch(cartProvider).value ?? const []),
);

/// "Mis pedidos" del dueño [ownerUid].
final ownerOrdersProvider = StreamProvider.autoDispose.family<List<ShopOrder>, String>(
  (ref, ownerUid) => ref.watch(shopRepositoryProvider).watchOwnerOrders(ownerUid),
  retry: (_, __) => null,
);

/// Pedidos pagados de la clínica [clinicId].
final clinicOrdersProvider = StreamProvider.autoDispose.family<List<ShopOrder>, String>(
  (ref, clinicId) => ref.watch(shopRepositoryProvider).watchClinicOrders(clinicId),
  retry: (_, __) => null,
);

/// Un pedido, o null si no existe.
final orderProvider = StreamProvider.autoDispose.family<ShopOrder?, String>(
  (ref, orderId) => ref.watch(shopRepositoryProvider).watchOrder(orderId),
  retry: (_, __) => null,
);
