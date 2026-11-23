import 'package:flutter/material.dart';

import '../comun/provisional_screen.dart';

/// Carrito (`/tienda/carrito`, RF-12 pasos 4-7): resumen, entrega y
/// "Confirmar compra" → `ShopRepository.createOrder` → Web Checkout de
/// Wompi. PROVISIONAL: la construye el Dev C.
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) => const ProvisionalScreen(
        title: 'Carrito',
        description: 'Tus productos, la entrega y el pago.',
        requirement: 'RF-12 · semana 6',
        fullScreen: true,
      );
}
