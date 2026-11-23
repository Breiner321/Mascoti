import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/shop_providers.dart';
import 'package:mascoti/core/data/shop_repository.dart';
import 'package:mascoti/core/domain/order.dart';
import 'package:mascoti/core/domain/product.dart';
import 'package:mascoti/core/theme/app_theme.dart';

/// Cuenta de la clínica `c1` (uid `vet`).
const clinicUser = AppUser(
  uid: 'vet',
  email: 'vet@correo.co',
  displayName: 'Vet',
  role: UserRole.clinica,
  clinicId: 'c1',
);

/// Repositorio sobre Firestore falso que registra los cambios de estado de
/// los pedidos en vez de llamar a `actualizar-pedido`.
class RecordingShopRepository extends ShopRepository {
  RecordingShopRepository(FakeFirebaseFirestore firestore) : super(firestore: firestore);

  final updates = <(String, OrderStatus, String?)>[];

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus estado, {String? motivo}) async {
    updates.add((orderId, estado, motivo));
  }
}

Future<void> addProduct(
  FakeFirebaseFirestore firestore,
  String id,
  String nombre, {
  int stock = 10,
  int precio = 45000,
  ProductStatus? estado,
}) =>
    firestore.doc('clinics/c1/products/$id').set({
      ...Product(
        id: id,
        clinicId: 'c1',
        nombre: nombre,
        categoria: ProductCategory.accesorio,
        precio: precio,
        stock: stock,
        fotoPath: 'vet/$id.jpg',
        estado: estado ?? ProductStatus.forStock(stock),
      ).toMap(),
      'stockReservado': 0,
    });

ShopOrder sampleOrder(
  String id,
  OrderStatus estado, {
  DeliveryType tipo = DeliveryType.recoger,
  DateTime? createdAt,
}) =>
    ShopOrder(
      id: id,
      ownerUid: 'u1',
      ownerNombre: 'Ana Pérez',
      clinicId: 'c1',
      clinicNombre: 'Vet',
      items: const [
        OrderItem(productId: 'p1', nombre: 'Collar', precio: 45000, cantidad: 2),
        OrderItem(productId: 'p2', nombre: 'Pelota', precio: 10000, cantidad: 1),
      ],
      total: 100000,
      entrega: OrderDelivery(
        tipo: tipo,
        telefono: '3001234567',
        direccion: tipo == DeliveryType.domicilio ? 'Calle 10 # 20-30, Bogotá' : null,
      ),
      estado: estado,
      referenciaPago: 'MSC-$id',
      createdAt: createdAt ?? DateTime(2026, 11, 18, 10),
    );

Future<void> addOrder(FakeFirebaseFirestore firestore, ShopOrder order) =>
    firestore.doc('orders/${order.id}').set(order.toMap());

/// Pantalla [home] en `/` dentro de un GoRouter con las rutas del plugin
/// como pantallas de texto (para comprobar la navegación).
Future<GoRouter> pumpClinicShop(
  WidgetTester tester, {
  required Widget home,
  required ShopRepository repository,
  List<Override> overrides = const [],
  ThemeData? theme,
  Map<String, Widget Function(GoRouterState)> extraRoutes = const {},
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(1080, height);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  addTearDown(() => AppColors.palette = AppPalette.light);

  Widget stub(GoRouterState state) => Scaffold(body: Text('Ruta ${state.uri}'));
  final routes = <String, Widget Function(GoRouterState)>{
    '/tienda/inventario/nuevo': stub,
    '/tienda/inventario/:id/editar': stub,
    '/tienda/clinica/pedidos': stub,
    '/tienda/clinica/pedidos/:id': stub,
    ...extraRoutes,
  };
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      for (final e in routes.entries) GoRoute(path: e.key, builder: (_, state) => e.value(state)),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(clinicUser),
        shopRepositoryProvider.overrideWithValue(repository),
        ...overrides,
      ],
      child: MaterialApp.router(theme: theme ?? AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
