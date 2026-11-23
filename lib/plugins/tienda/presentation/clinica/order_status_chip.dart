import 'package:flutter/material.dart';

import '../../../../core/domain/order.dart';
import '../../../../core/theme/app_theme.dart';
import 'status_pill.dart';

/// Estado del pedido con ícono y texto (no solo color).
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      OrderStatus.pagado => (Icons.payments_outlined, AppColors.primary),
      OrderStatus.preparando => (Icons.inventory_outlined, AppColors.slotBlocked),
      OrderStatus.listo => (Icons.storefront_outlined, AppColors.success),
      OrderStatus.enviado => (Icons.local_shipping_outlined, AppColors.success),
      OrderStatus.entregado => (Icons.task_alt, AppColors.success),
      OrderStatus.cancelado => (Icons.cancel_outlined, AppColors.sosText),
      OrderStatus.pendientePago || OrderStatus.pagoRechazado || OrderStatus.expirado => (
          Icons.hourglass_empty,
          AppColors.textMuted
        ),
    };
    return StatusPill(icon: icon, color: color, label: status.label);
  }
}
