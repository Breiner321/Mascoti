import 'package:flutter/material.dart';

import '../../../../core/domain/order.dart';
import '../../../../core/format/relative_time.dart';
import '../../../../core/theme/app_theme.dart';
import '../comun/price_format.dart';
import 'delivery_line.dart';
import 'order_status_chip.dart';

/// Pedido recibido en la lista: cliente, productos, total, entrega y
/// estado.
class ClinicOrderCard extends StatelessWidget {
  const ClinicOrderCard({super.key, required this.order, required this.onTap, this.now});

  final ShopOrder order;
  final VoidCallback onTap;

  /// Hora actual (fija en las pruebas).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted);
    final createdAt = order.createdAt;
    final items = [for (final i in order.items) '${i.cantidad} × ${i.nombre}'].join(', ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    order.ownerNombre.isEmpty ? 'Cliente' : order.ownerNombre,
                    style: theme.textTheme.titleMedium,
                  ),
                  OrderStatusChip(status: order.estado),
                ],
              ),
              const SizedBox(height: 4),
              Text(items, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('Total: ${formatCop(order.total)}', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              DeliveryLine(delivery: order.entrega, style: muted),
              if (createdAt != null) ...[
                const SizedBox(height: 4),
                Text(relativeTime(createdAt, now ?? DateTime.now()), style: muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
