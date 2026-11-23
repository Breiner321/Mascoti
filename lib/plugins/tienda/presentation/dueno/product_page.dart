import 'package:flutter/material.dart';

import '../comun/provisional_screen.dart';

/// Detalle de un producto (`/tienda/producto/:id?clinicId=`, RF-12 paso 2).
/// PROVISIONAL: la construye el Dev C con `productProvider` y
/// `ShopRepository.addToCart`.
class ProductPage extends StatelessWidget {
  const ProductPage({super.key, required this.productId, required this.clinicId});

  final String productId;
  final String? clinicId;

  @override
  Widget build(BuildContext context) => const ProvisionalScreen(
        title: 'Producto',
        description: 'Detalle del producto y "Agregar al carrito".',
        requirement: 'RF-12 · semana 6',
        fullScreen: true,
      );
}
