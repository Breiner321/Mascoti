import 'package:flutter/material.dart';

import '../comun/provisional_screen.dart';

/// Pestaña "Tienda" del dueño (`/tienda`, RF-12): catálogo general o de
/// "Mi clínica favorita". PROVISIONAL: la construye el Dev C con
/// `catalogProvider` / `clinicProductsProvider`.
class StorePage extends StatelessWidget {
  const StorePage({super.key});

  @override
  Widget build(BuildContext context) => const ProvisionalScreen(
        title: 'Tienda',
        description: 'Productos de las clínicas para tu mascota.',
        requirement: 'RF-12 · semana 6',
      );
}
