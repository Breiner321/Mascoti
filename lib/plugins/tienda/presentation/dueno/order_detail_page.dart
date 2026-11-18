import 'package:flutter/material.dart';

import '../comun/provisional_screen.dart';

/// Detalle de un pedido (`/tienda/pedidos/:id`): seguimiento y espera del
/// pago (el webhook de Wompi cambia el estado). Destino de las
/// notificaciones del dueño. PROVISIONAL: la construye el Dev C con
/// `orderProvider`.
class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) => const ProvisionalScreen(
        title: 'Pedido',
        description: 'Seguimiento de tu pedido.',
        requirement: 'RF-12 · semana 6',
        fullScreen: true,
      );
}
