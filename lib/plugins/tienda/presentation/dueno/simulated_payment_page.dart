import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/shop_providers.dart';
import '../../../../core/data/shop_repository.dart';
import '../../../../core/domain/order.dart';
import '../../../../core/format/bogota_time.dart';
import '../../../../core/format/time_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../tienda_routes.dart';
import '../comun/price_format.dart';
import '../comun/shop_message.dart';

/// Pago de PRUEBA de un pedido (`/tienda/pedidos/:id/pagar`, Cambio 5):
/// mientras no haya pasarela real, el checkout abre esta pantalla cuando
/// `CheckoutSession.isSimulated`. No mueve dinero: el servidor
/// (`pagar-pedido-simulado`) registra el resultado igual que lo haría una
/// pasarela (stock, carrito y avisos) y la pantalla lo ve llegar en tiempo
/// real.
class SimulatedPaymentPage extends ConsumerStatefulWidget {
  const SimulatedPaymentPage({super.key, required this.orderId, this.now});

  final String orderId;

  /// Hora actual (fija en las pruebas).
  final DateTime? now;

  @override
  ConsumerState<SimulatedPaymentPage> createState() => _SimulatedPaymentPageState();
}

class _SimulatedPaymentPageState extends ConsumerState<SimulatedPaymentPage> {
  bool _busy = false;

  Future<void> _pay({required bool approve}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(shopRepositoryProvider).paySimulated(widget.orderId, approve: approve);
    } on ShopFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo registrar el pago. Intenta de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Pagar pedido')),
      body: SafeArea(
        child: switch (order) {
          AsyncValue(:final ShopOrder value) => _buildFor(value),
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

  Widget _buildFor(ShopOrder order) {
    final now = widget.now ?? DateTime.now();
    final expiraEn = order.expiraEn;
    final expired = expiraEn != null && !expiraEn.isAfter(now);
    return switch (order.estado) {
      OrderStatus.pagado ||
      OrderStatus.preparando ||
      OrderStatus.listo ||
      OrderStatus.enviado ||
      OrderStatus.entregado =>
        ShopMessage(
          icon: Icons.check_circle_outline,
          text: '¡Pedido realizado con éxito!',
          action: FilledButton(
            onPressed: () => context.go(TiendaRoutes.order(order.id)),
            child: const Text('Ver mi pedido'),
          ),
        ),
      OrderStatus.pagoRechazado => ShopMessage(
          icon: Icons.credit_card_off_outlined,
          text: 'Tu pago no pudo ser procesado. Tus productos siguen en el carrito.',
          action: FilledButton(
            onPressed: () => context.go(TiendaRoutes.cart),
            child: const Text('Volver al carrito'),
          ),
        ),
      OrderStatus.pendientePago when order.pasarela != PaymentGateway.simulada => const ShopMessage(
          icon: Icons.info_outline,
          text: 'Este pedido no admite pagos de prueba.',
        ),
      OrderStatus.pendientePago when !expired => _buildPayment(order),
      _ => ShopMessage(
          icon: Icons.timer_off_outlined,
          text: 'El tiempo para pagar este pedido terminó. Vuelve a confirmar la compra.',
          action: FilledButton(
            onPressed: () => context.go(TiendaRoutes.cart),
            child: const Text('Volver al carrito'),
          ),
        ),
    };
  }

  Widget _buildPayment(ShopOrder order) {
    final theme = Theme.of(context);
    final expiraEn = order.expiraEn;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _TestPaymentNotice(),
        const SizedBox(height: 16),
        Text(order.clinicNombre, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
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
        if (expiraEn != null) ...[
          const SizedBox(height: 8),
          Text(
            // La hora ya termina en punto ('a. m.').
            'Tus productos están apartados hasta las ${_hour(expiraEn)}',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: 24),
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: _busy ? null : () => _pay(approve: true),
          icon: const Icon(Icons.lock_outline),
          label: Text('Pagar ${formatCop(order.total)}'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : () => _pay(approve: false),
          child: const Text('Simular pago rechazado'),
        ),
      ],
    );
  }

  /// Hora de Colombia en formato de 12 horas ("3:15 p. m.").
  static String _hour(DateTime instant) {
    final local = BogotaTime.wallClock(instant);
    return TimeFormat.ofTime(TimeOfDay(hour: local.hour, minute: local.minute));
  }
}

/// Aviso visible de que es una compra de prueba.
class _TestPaymentNotice extends StatelessWidget {
  const _TestPaymentNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slotBlockedContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slotBlocked),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: AppColors.slotBlocked),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Pago de prueba: no se cobra dinero real. La pasarela de pagos se '
              'conectará más adelante.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
