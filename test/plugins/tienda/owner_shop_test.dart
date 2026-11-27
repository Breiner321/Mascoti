import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/shop_providers.dart';
import 'package:mascoti/core/data/shop_repository.dart';
import 'package:mascoti/core/domain/cart_item.dart';
import 'package:mascoti/core/domain/order.dart';
import 'package:mascoti/core/domain/product.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/tienda/presentation/dueno/cart_page.dart';
import 'package:mascoti/plugins/tienda/presentation/dueno/checkout_page.dart';
import 'package:mascoti/plugins/tienda/presentation/dueno/order_detail_page.dart';
import 'package:mascoti/plugins/tienda/presentation/dueno/owner_shop_providers.dart';
import 'package:mascoti/plugins/tienda/presentation/dueno/product_page.dart';
import 'package:mascoti/plugins/tienda/presentation/dueno/store_page.dart';
import 'package:mocktail/mocktail.dart';

import '../../a11y.dart';
import '../../core/fake_plugins.dart';

class _MockShop extends Mock implements ShopRepository {}

const ana = AppUser(
  uid: 'ana',
  email: 'ana@example.com',
  displayName: 'Ana',
  role: UserRole.dueno,
  telefono: '3001234567',
);

Product product(String id, String nombre, {int precio = 45000, int stock = 5, ProductCategory cat = ProductCategory.alimento}) =>
    Product(
      id: id,
      clinicId: 'c1',
      nombre: nombre,
      categoria: cat,
      precio: precio,
      stock: stock,
      fotoPath: '',
      estado: stock == 0 ? ProductStatus.agotado : ProductStatus.activo,
    );

final concentrado = product('p1', 'Concentrado 2 kg');
final pelota = product('p2', 'Pelota de goma', precio: 12000, cat: ProductCategory.juguete);
final snacks = product('p3', 'Snacks dentales', precio: 18000, stock: 0);

void main() {
  late _MockShop shop;

  setUpAll(() => registerFallbackValue(concentrado));
  setUp(() => shop = _MockShop());

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    List<Override> overrides = const [],
    ThemeData? theme,
    Map<String, String> visited = const {'c1': 'Vet Norte', 'c2': 'Vet Sur'},
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => Scaffold(body: page)),
      GoRoute(path: '/tienda/producto/:id', builder: (_, s) => Text('producto ${s.pathParameters['id']}')),
      GoRoute(path: '/tienda/carrito', builder: (_, __) => const Text('carrito')),
      GoRoute(path: '/tienda/checkout', builder: (_, __) => const Text('checkout')),
      GoRoute(path: '/tienda/pedidos/:id/pagar', builder: (_, s) => Text('pagar ${s.pathParameters['id']}')),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(ana),
        shopRepositoryProvider.overrideWithValue(shop),
        visitedClinicsProvider.overrideWithValue(visited),
        shopClinicProvider.overrideWith((ref, id) => Stream.value(null)),
        shopClockProvider.overrideWithValue(() => DateTime(2026, 11, 23, 10)),
        pluginRegistryProvider.overrideWithValue(PluginRegistry([
          FakePlugin('chat', roles: {UserRole.dueno}, paths: ['/chat', '/chat/abrir']),
        ])),
        ...overrides,
      ],
      child: MaterialApp.router(theme: theme ?? AppTheme.light(), routerConfig: router),
    ));
    // Con un indicador de progreso indefinido no se puede esperar a que todo
    // se quede quieto.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('catálogo', () {
    List<Override> catalog({List<CartItem> cart = const []}) => [
          clinicProductsProvider('c1').overrideWith((ref) => Stream.value([concentrado, pelota, snacks])),
          cartProvider.overrideWith((ref) => Stream.value(cart)),
        ];

    testWidgets('agotado lleva la etiqueta y no tiene botón de agregar', (tester) async {
      await pump(tester, const StorePage(), overrides: catalog());

      expect(find.text('Clínica: Vet Norte'), findsOneWidget);
      expect(find.text('Snacks dentales'), findsOneWidget);
      expect(find.text('Agotado'), findsOneWidget);
      expect(find.byTooltip('Agregar Snacks dentales al carrito'), findsNothing);
      expect(find.byTooltip('Agregar Concentrado 2 kg al carrito'), findsOneWidget);
    });

    testWidgets('filtra por categoría y por nombre', (tester) async {
      await pump(tester, const StorePage(), overrides: catalog());

      await tester.tap(find.widgetWithText(ChoiceChip, 'Juguete'));
      await tester.pumpAndSettle();
      expect(find.text('Pelota de goma'), findsOneWidget);
      expect(find.text('Concentrado 2 kg'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Todos'));
      await tester.enterText(find.byType(TextField), 'snack');
      await tester.pumpAndSettle();
      expect(find.text('Snacks dentales'), findsOneWidget);
      expect(find.text('Pelota de goma'), findsNothing);
    });

    testWidgets('la tarjeta se lee completa con TalkBack', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const StorePage(), overrides: catalog());
      expect(find.bySemanticsLabel('Snacks dentales, 18.000 pesos, agotado'), findsOneWidget);
      expect(find.bySemanticsLabel('Concentrado 2 kg, 45.000 pesos'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('agregar desde la tarjeta usa el repositorio', (tester) async {
      when(() => shop.addToCart('ana', any(), 1, replaceOtherClinic: false)).thenAnswer((_) async {});
      await pump(tester, const StorePage(), overrides: catalog());
      await tester.tap(find.byTooltip('Agregar Pelota de goma al carrito'));
      await tester.pumpAndSettle();
      verify(() => shop.addToCart('ana', pelota, 1, replaceOtherClinic: false)).called(1);
      expect(find.text('Pelota de goma se agregó al carrito'), findsOneWidget);
    });

    testWidgets('sin clínicas conocidas pide elegir una', (tester) async {
      await pump(tester, const StorePage(), visited: const {}, overrides: [
        cartProvider.overrideWith((ref) => Stream.value(const [])),
      ]);
      expect(find.text(StorePage.noClinic), findsOneWidget);
    });
  });

  group('producto', () {
    List<Override> productOv(Product p, {List<CartItem> cart = const []}) => [
          productProvider((clinicId: 'c1', productId: p.id)).overrideWith((ref) => Stream.value(p)),
          cartProvider.overrideWith((ref) => Stream.value(cart)),
        ];

    testWidgets('la cantidad no pasa del stock', (tester) async {
      when(() => shop.addToCart('ana', any(), any(), replaceOtherClinic: false)).thenAnswer((_) async {});
      final p = product('p9', 'Collar', stock: 2);
      await pump(tester, const ProductPage(productId: 'p9', clinicId: 'c1'), overrides: productOv(p));

      final more = find.byTooltip('Aumentar cantidad de Collar');
      await tester.tap(more);
      await tester.pump();
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add).last).onPressed, isNull);

      await tester.tap(find.text('Agregar al carrito'));
      await tester.pumpAndSettle();
      verify(() => shop.addToCart('ana', p, 2, replaceOtherClinic: false)).called(1);
    });

    testWidgets('sin conexión "Agregar al carrito" no se queda girando', (tester) async {
      // Firestore deja la escritura en cola: su Future no termina sin red.
      when(() => shop.addToCart('ana', any(), any(), replaceOtherClinic: false))
          .thenAnswer((_) => Completer<void>().future);
      final p = product('p9', 'Collar', stock: 2);
      await pump(tester, const ProductPage(productId: 'p9', clinicId: 'c1'), overrides: productOv(p));

      await tester.tap(find.text('Agregar al carrito'));
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      expect(find.text('Sin conexión: se guardará cuando vuelva la red.'), findsOneWidget);
      final button = tester.widget<FilledButton>(
          find.ancestor(of: find.text('Agregar al carrito'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('carrito de otra clínica: pregunta y vacía al aceptar', (tester) async {
      var calls = 0;
      when(() => shop.addToCart('ana', any(), any(), replaceOtherClinic: any(named: 'replaceOtherClinic')))
          .thenAnswer((inv) async {
        calls++;
        if (inv.namedArguments[#replaceOtherClinic] != true) throw const CartFromOtherClinic();
      });
      await pump(
        tester,
        const ProductPage(productId: 'p1', clinicId: 'c1'),
        overrides: productOv(concentrado, cart: const [
          CartItem(productId: 'x', clinicId: 'c2', nombre: 'Arena', precio: 30000, cantidad: 1),
        ]),
      );

      await tester.tap(find.text('Agregar al carrito'));
      // El botón muestra un indicador mientras espera la respuesta.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tu carrito tiene productos de Vet Sur. ¿Vaciarlo y agregar este?'), findsOneWidget);

      await tester.tap(find.text('Vaciar y agregar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 2);
      verify(() => shop.addToCart('ana', concentrado, 1, replaceOtherClinic: true)).called(1);
    });

    testWidgets('agotado: sin selector ni botón', (tester) async {
      await pump(tester, const ProductPage(productId: 'p3', clinicId: 'c1'), overrides: productOv(snacks));
      expect(find.text('Agregar al carrito'), findsNothing);
      expect(find.text('Agotado'), findsOneWidget);
    });
  });

  group('carrito', () {
    List<Override> cartOv(List<CartItem> items, Map<String, Product> current) => [
          cartProvider.overrideWith((ref) => Stream.value(items)),
          for (final i in items)
            productProvider((clinicId: 'c1', productId: i.productId))
                .overrideWith((ref) => Stream.value(current[i.productId])),
        ];

    testWidgets('subtotal de referencia y avisos de agotado y precio', (tester) async {
      await pump(tester, const CartPage(), overrides: cartOv(const [
        CartItem(productId: 'p1', clinicId: 'c1', nombre: 'Concentrado 2 kg', precio: 40000, cantidad: 2),
        CartItem(productId: 'p3', clinicId: 'c1', nombre: 'Snacks dentales', precio: 18000, cantidad: 1),
      ], {'p1': concentrado, 'p3': snacks}));

      expect(find.text(CartPage.referenceNote), findsOneWidget);
      expect(find.text(r'El precio cambió de $ 40.000 a $ 45.000.'), findsOneWidget);
      expect(find.text('Se agotó. Quítalo del carrito para continuar.'), findsOneWidget);
      // Un agotado no deja continuar.
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar con la compra')).onPressed,
        isNull,
      );
    });

    testWidgets('sin problemas se puede continuar', (tester) async {
      await pump(tester, const CartPage(), overrides: cartOv(const [
        CartItem(productId: 'p1', clinicId: 'c1', nombre: 'Concentrado 2 kg', precio: 45000, cantidad: 2),
      ], {'p1': concentrado}));
      expect(find.text(r'$ 90.000'), findsWidgets);
      await tester.tap(find.text('Continuar con la compra'));
      await tester.pumpAndSettle();
      expect(find.text('checkout'), findsOneWidget);
    });

    testWidgets('vacío', (tester) async {
      await pump(tester, const CartPage(), overrides: [cartProvider.overrideWith((ref) => Stream.value(const []))]);
      expect(find.text('Tu carrito está vacío.'), findsOneWidget);
    });

    testWidgets('confirmar compra: si el carrito no carga, error con Reintentar (no cargando para siempre)',
        (tester) async {
      await pump(tester, const CheckoutPage(), overrides: [
        cartProvider.overrideWith((ref) => Stream.error(Exception('sin permiso'))),
      ]);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No pudimos cargar tu carrito.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('confirmar compra con el carrito vacío: "Ir a la tienda" no lanza excepciones',
        (tester) async {
      await pump(tester, const CheckoutPage(), overrides: [
        cartProvider.overrideWith((ref) => Stream.value(const [])),
      ]);
      expect(find.text('Tu carrito está vacío.'), findsOneWidget);
      // Desmontar la pantalla (como al salir de ella).
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });

  group('resultado del pago', () {
    ShopOrder order(OrderStatus estado) => ShopOrder(
          id: 'o1',
          ownerUid: 'ana',
          ownerNombre: 'Ana',
          clinicId: 'c1',
          clinicNombre: 'Vet Norte',
          items: const [OrderItem(productId: 'p1', nombre: 'Concentrado 2 kg', precio: 45000, cantidad: 2)],
          total: 90000,
          entrega: const OrderDelivery(tipo: DeliveryType.recoger, telefono: '3001234567'),
          estado: estado,
          referenciaPago: 'MSC-o1',
          expiraEn: DateTime.utc(2026, 11, 23, 15, 15), // 10:15 a. m. en Bogotá
        );

    testWidgets('"Confirmando tu pago…" hasta que el servidor responde', (tester) async {
      final updates = StreamController<ShopOrder?>.broadcast();
      addTearDown(() {
        updates.close();
      });
      await pump(tester, const OrderDetailPage(orderId: 'o1'), settle: false, overrides: [
        orderProvider('o1').overrideWith((ref) => updates.stream),
      ]);
      updates.add(order(OrderStatus.pendientePago));
      await tester.pump();

      expect(find.text(OrderDetailPage.confirming), findsOneWidget);
      expect(
        find.text('Si no completas el pago, el pedido se cancela solo a los 15 minutos (a las 10:15 a. m.).'),
        findsOneWidget,
      );

      // El webhook (o el pago de prueba) lo actualiza en tiempo real.
      updates.add(order(OrderStatus.pagado));
      await tester.pump();
      expect(find.text(OrderDetailPage.confirming), findsNothing);
      expect(find.text(OrderDetailPage.approved), findsOneWidget);
      expect(find.text('Pagado'), findsWidgets);
    });

    testWidgets('pago rechazado: "Intentar de nuevo" lleva al carrito', (tester) async {
      await pump(tester, const OrderDetailPage(orderId: 'o1'), overrides: [
        orderProvider('o1').overrideWith((ref) => Stream.value(order(OrderStatus.pagoRechazado))),
      ]);
      // El chip de estado también dice "Pago rechazado".
      expect(find.text(OrderDetailPage.rejected), findsWidgets);
      await tester.tap(find.text('Intentar de nuevo'));
      await tester.pumpAndSettle();
      expect(find.text('carrito'), findsOneWidget);
    });

    testWidgets('pendiente con pago de prueba: "Ir a pagar"', (tester) async {
      await pump(tester, const OrderDetailPage(orderId: 'o1'), settle: false, overrides: [
        orderProvider('o1').overrideWith((ref) => Stream.value(order(OrderStatus.pendientePago))),
      ]);
      await tester.tap(find.text('Ir a pagar'));
      await tester.pumpAndSettle();
      expect(find.text('pagar o1'), findsOneWidget);
    });
  });

  group('accesibilidad (Cambio 3)', () {
    List<Override> catalog() => [
          clinicProductsProvider('c1').overrideWith((ref) => Stream.value([concentrado, pelota, snacks])),
          cartProvider.overrideWith((ref) => Stream.value(const [])),
        ];

    testWidgets('catálogo: áreas táctiles, etiquetas y contraste', (tester) async {
      await pump(tester, const StorePage(), overrides: catalog());
      await expectAccessible(tester);
    });

    testWidgets('catálogo en modo oscuro', (tester) async {
      await pump(tester, const StorePage(), overrides: catalog(), theme: AppTheme.of(AppPalette.dark));
      await expectAccessible(tester);
      AppTheme.light();
    });

    testWidgets('catálogo con texto al 200 %', (tester) async {
      useLargeText(tester);
      await pump(tester, const StorePage(), overrides: catalog());
      expectNoOverflow(tester);
    });

    testWidgets('producto con texto al 200 %', (tester) async {
      useLargeText(tester);
      await pump(tester, const ProductPage(productId: 'p1', clinicId: 'c1'), overrides: [
        productProvider((clinicId: 'c1', productId: 'p1')).overrideWith((ref) => Stream.value(concentrado)),
        cartProvider.overrideWith((ref) => Stream.value(const [])),
      ]);
      expectNoOverflow(tester);
    });
  });
}
