import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import '../../core/router/navigator_keys.dart';
import 'presentation/clinica/clinic_order_detail_page.dart';
import 'presentation/clinica/clinic_orders_page.dart';
import 'presentation/clinica/clinic_shop_providers.dart';
import 'presentation/clinica/inventory_page.dart';
import 'presentation/clinica/product_form_page.dart';
import 'presentation/dueno/cart_page.dart';
import 'presentation/dueno/order_detail_page.dart';
import 'presentation/dueno/owner_orders_page.dart';
import 'presentation/dueno/product_page.dart';
import 'presentation/dueno/simulated_payment_page.dart';
import 'presentation/dueno/store_page.dart';
import 'tienda_routes.dart';

/// Plugin compartido: tienda y carrito del dueño (RF-12) e inventario y
/// pedidos de la clínica (RF-07). Datos en `core/data/shop_repository.dart`;
/// el pago y los cambios de estado de los pedidos los hacen las Edge
/// Functions.
class TiendaPlugin extends MascotiPlugin {
  const TiendaPlugin();

  @override
  String get id => 'tienda';

  @override
  Set<UserRole> get roles => const {UserRole.dueno, UserRole.clinica};

  @override
  List<RouteBase> routes() => [
        GoRoute(path: TiendaRoutes.store, builder: (context, state) => const StorePage()),
        GoRoute(
          path: TiendaRoutes.productPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => ProductPage(
            productId: state.pathParameters['id']!,
            clinicId: state.uri.queryParameters['clinicId'],
          ),
        ),
        GoRoute(
          path: TiendaRoutes.cart,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const CartPage(),
        ),
        GoRoute(
          path: TiendaRoutes.ownerOrders,
          builder: (context, state) => const OwnerOrdersPage(),
        ),
        GoRoute(
          path: TiendaRoutes.orderPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => OrderDetailPage(orderId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: TiendaRoutes.payOrderPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => SimulatedPaymentPage(orderId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: TiendaRoutes.inventory,
          builder: (context, state) => const InventoryPage(),
        ),
        GoRoute(
          path: TiendaRoutes.newProduct,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const ProductFormPage(),
        ),
        GoRoute(
          path: TiendaRoutes.editProductPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => ProductFormPage(productId: state.pathParameters['id']),
        ),
        GoRoute(
          path: TiendaRoutes.clinicOrders,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const ClinicOrdersPage(),
        ),
        GoRoute(
          path: TiendaRoutes.clinicOrderPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => ClinicOrderDetailPage(orderId: state.pathParameters['id']!),
        ),
      ];

  /// Dueño: "Tienda" entre "Mapa" (10) y "Citas" (30). Clínica:
  /// "Inventario" después de "Agenda" (20) y antes de "Mensajes" (30), con
  /// el número de pedidos pagados por preparar.
  @override
  List<PluginDestination> destinations(UserRole role) => switch (role) {
        UserRole.dueno => const [
            PluginDestination(
              label: 'Tienda',
              icon: Icons.storefront_outlined,
              selectedIcon: Icons.storefront,
              path: TiendaRoutes.store,
              order: 20,
            ),
          ],
        UserRole.clinica => [
            PluginDestination(
              label: 'Inventario',
              icon: Icons.inventory_2_outlined,
              selectedIcon: Icons.inventory_2,
              path: TiendaRoutes.inventory,
              order: 25,
              badge: pendingClinicOrdersCountProvider,
            ),
          ],
      };
}
