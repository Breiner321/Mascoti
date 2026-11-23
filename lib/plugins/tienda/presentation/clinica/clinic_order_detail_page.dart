import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/shop_providers.dart';
import '../../../../core/data/shop_repository.dart';
import '../../../../core/domain/order.dart';
import '../../../../core/format/relative_time.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/clinic_order_rules.dart';
import '../comun/price_format.dart';
import '../comun/shop_message.dart';
import 'cancel_order_dialog.dart';
import 'delivery_line.dart';
import 'order_status_chip.dart';

/// Detalle de un pedido recibido (`/tienda/clinica/pedidos/:id`, RF-07):
/// productos, total, entrega y el botón del siguiente paso según la máquina
/// de estados. Todos los cambios van por la Edge Function
/// `actualizar-pedido` (`ShopRepository.updateOrderStatus`).
class ClinicOrderDetailPage extends ConsumerStatefulWidget {
  const ClinicOrderDetailPage({super.key, required this.orderId, this.now});

  final String orderId;

  /// Hora actual (fija en las pruebas).
  final DateTime? now;

  @override
  ConsumerState<ClinicOrderDetailPage> createState() => _ClinicOrderDetailPageState();
}

class _ClinicOrderDetailPageState extends ConsumerState<ClinicOrderDetailPage> {
  bool _busy = false;

  Future<void> _update(OrderStatus to, {String? motivo, required String done}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(shopRepositoryProvider).updateOrderStatus(widget.orderId, to, motivo: motivo);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ShopFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar el pedido. Intenta de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final motivo = await showCancelOrderDialog(context);
    if (motivo == null || !mounted) return;
    await _update(OrderStatus.cancelado, motivo: motivo, done: 'Pedido cancelado');
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del pedido')),
      body: SafeArea(
        child: switch (order) {
          AsyncValue(:final ShopOrder value) => _buildDetail(value),
          AsyncData() => const ShopMessage(
              icon: Icons.search_off,
              text: 'No encontramos este pedido.',
            ),
          AsyncError() => ShopMessage(
              icon: Icons.cloud_off,
              text: 'No se pudo cargar el pedido.',
              action: FilledButton(
                onPressed: () => ref.invalidate(orderProvider(widget.orderId)),
                child: const Text('Reintentar'),
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _buildDetail(ShopOrder order) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted);
    final next = ClinicOrderRules.nextAction(order);
    final canCancel = ClinicOrderRules.canCancel(order);
    final createdAt = order.createdAt;
    final motivo = order.motivoCancelacion;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              order.ownerNombre.isEmpty ? 'Cliente' : order.ownerNombre,
              style: theme.textTheme.titleLarge,
            ),
            OrderStatusChip(status: order.estado),
          ],
        ),
        if (createdAt != null) ...[
          const SizedBox(height: 4),
          Text('Recibido: ${relativeTime(createdAt, widget.now ?? DateTime.now())}', style: muted),
        ],
        const SizedBox(height: 16),
        Text('Productos', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('${item.cantidad} × ${item.nombre}')),
                const SizedBox(width: 8),
                Text(formatCop(item.subtotal)),
              ],
            ),
          ),
        const Divider(),
        Row(
          children: [
            Expanded(child: Text('Total', style: theme.textTheme.titleMedium)),
            Text(formatCop(order.total), style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 16),
        Text('Entrega', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        DeliveryLine(delivery: order.entrega),
        if (order.entrega.tipo == DeliveryType.domicilio) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.phone_outlined, size: 20, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text('Tel. ${order.entrega.telefono}')),
            ],
          ),
        ],
        if (order.estado == OrderStatus.cancelado && motivo != null) ...[
          const SizedBox(height: 16),
          Text('Motivo de la cancelación', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(motivo),
        ],
        const SizedBox(height: 24),
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        if (next != null)
          FilledButton(
            onPressed:
                _busy ? null : () => _update(next.to, done: 'Pedido actualizado: ${next.to.label}'),
            child: Text(next.label),
          ),
        if (canCancel) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _cancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancelar pedido'),
          ),
        ],
      ],
    );
  }
}
