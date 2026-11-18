import 'package:flutter/material.dart';

import '../comun/provisional_screen.dart';

/// "Mis pedidos" del dueño (`/tienda/pedidos`). PROVISIONAL: la construye
/// el Dev C con `ownerOrdersProvider`.
class OwnerOrdersPage extends StatelessWidget {
  const OwnerOrdersPage({super.key});

  @override
  Widget build(BuildContext context) => const ProvisionalScreen(
        title: 'Mis pedidos',
        description: 'El estado de tus compras.',
        requirement: 'RF-12 · semana 6',
      );
}
