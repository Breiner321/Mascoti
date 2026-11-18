import 'package:flutter/material.dart';

import '../comun/provisional_screen.dart';

/// Pestaña "Inventario" de la clínica (`/tienda/inventario`, RF-07).
/// PROVISIONAL: la construye el Dev B con `inventoryProvider` y los métodos
/// de productos de `ShopRepository`.
class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) => const ProvisionalScreen(
        title: 'Inventario',
        description: 'Los productos de tu tienda y su stock.',
        requirement: 'RF-07 · semana 6',
      );
}
