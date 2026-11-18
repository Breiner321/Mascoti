import 'package:flutter/material.dart';

import '../comun/provisional_screen.dart';

/// Pedidos recibidos por la clínica (`/tienda/clinica/pedidos`): destino de
/// la notificación "Nuevo pedido". PROVISIONAL: la construye el Dev B con
/// `clinicOrdersProvider` y `ShopRepository.updateOrderStatus`.
class ClinicOrdersPage extends StatelessWidget {
  const ClinicOrdersPage({super.key});

  @override
  Widget build(BuildContext context) => const ProvisionalScreen(
        title: 'Pedidos',
        description: 'Pedidos pagados para preparar y entregar.',
        requirement: 'RF-12 · semana 6',
        fullScreen: true,
      );
}
