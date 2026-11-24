import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/shop_providers.dart';
import '../../../../core/domain/order.dart';
import '../../../../core/format/bogota_time.dart';
import '../../../../core/format/time_format.dart';
import '../../../../core/kernel/plugin_registry.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/order_timeline.dart';
import '../../tienda_routes.dart';
import '../clinica/order_status_chip.dart';
import '../comun/price_format.dart';
import '../comun/shop_message.dart';
import 'owner_shop_providers.dart';

/// Detalle de un pedido del dueño (`/tienda/pedidos/:id`, RF-12), en tiempo
/// real. El resultado del pago sale SOLO del estado en Firestore (lo pone
/// el servidor), nunca de la URL de regreso de la pasarela.
class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  static const confirming = 'Confirmando tu pago…';
  static const approved = 'Pago aprobado';
  static const rejected = 'Pago rechazado';

  /// "Si no completas el pago, el pedido se cancela solo a los 15 minutos
  /// (a las 10:45 a. m.)."
  static String expiryNotice(DateTime? expiraEn) {
    final base = 'Si no completas el pago, el pedido se cancela solo a los '
        '${OrderLimits.reservaMin} minutos';
    if (expiraEn == null) return '$base.';
    final w = BogotaTime.wallClock(expiraEn);
    return '$base (a las ${TimeFormat.ofTime(TimeOfDay(hour: w.hour, minute: w.minute))}).';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));
    Widget scaffold(Widget body) =>
        Scaffold(appBar: AppBar(title: const Text('Mi pedido')), body: body);
    return switch (order) {
      AsyncValue(value: final ShopOrder o) => scaffold(_OrderBody(order: o)),
      AsyncData() => scaffold(const ShopMessage(
          icon: Icons.search_off, text: 'No encontramos este pedido.')),
      AsyncError() => scaffold(ShopMessage(
          icon: Icons.cloud_off,
          text: 'No pudimos cargar el pedido.',
          action: FilledButton(
            onPressed: () => ref.invalidate(orderProvider(orderId)),
            child: const Text('Reintentar'),
          ),
        )),
      _ => scaffold(const Center(child: CircularProgressIndicator())),
    };
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final now = ref.read(shopClockProvider)();
    final o = order;
    final timeline = orderTimeline(o);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(o.clinicNombre,
                  style: textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            OrderStatusChip(status: o.estado),
          ],
        ),
        const SizedBox(height: 12),
        _PaymentState(order: o, now: now),
        if (timeline.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Timeline(steps: timeline),
        ],
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text('Productos',
              style:
                  textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 6),
        for (final item in o.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('${item.cantidad} × ${item.nombre}')),
                Text(formatCop(item.subtotal)),
              ],
            ),
          ),
        const Divider(),
        Row(
          children: [
            Expanded(child: Text('Total', style: textTheme.titleMedium)),
            Text(formatCop(o.total),
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 12),
        _Line(
          icon: o.entrega.tipo == DeliveryType.domicilio
              ? Icons.local_shipping_outlined
              : Icons.storefront_outlined,
          text: o.entrega.tipo == DeliveryType.domicilio
              ? 'Domicilio: ${o.entrega.direccion ?? ''}'
              : o.entrega.tipo.label,
        ),
        _Line(icon: Icons.phone_outlined, text: o.entrega.telefono),
        const SizedBox(height: 16),
        _ContactButtons(order: o),
      ],
    );
  }
}

/// "Confirmando tu pago…", "Pago aprobado" o "Pago rechazado".
class _PaymentState extends StatelessWidget {
  const _PaymentState({required this.order, required this.now});

  final ShopOrder order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final expired = o.estado == OrderStatus.expirado ||
        (o.estado == OrderStatus.pendientePago &&
            o.expiraEn != null &&
            !o.expiraEn!.isAfter(now));
    if (expired) {
      return _Banner(
        icon: Icons.timer_off_outlined,
        color: AppColors.slotLocked,
        background: AppColors.slotLockedContainer,
        title: 'El tiempo para pagar terminó',
        text:
            'Tus productos siguen en el carrito. Vuelve a confirmar la compra.',
        action: FilledButton(
            onPressed: () => context.go(TiendaRoutes.cart),
            child: const Text('Volver al carrito')),
      );
    }
    return switch (o.estado) {
      OrderStatus.pendientePago => _Banner(
          icon: Icons.hourglass_top,
          color: AppColors.slotBlocked,
          background: AppColors.slotBlockedContainer,
          title: OrderDetailPage.confirming,
          text: OrderDetailPage.expiryNotice(o.expiraEn),
          busy: true,
          action: o.pasarela == PaymentGateway.simulada
              ? FilledButton(
                  onPressed: () => context.push(TiendaRoutes.payOrder(o.id)),
                  child: const Text('Ir a pagar'),
                )
              : null,
        ),
      OrderStatus.pagoRechazado => _Banner(
          icon: Icons.credit_card_off_outlined,
          color: AppColors.sosText,
          background: AppColors.sosContainer,
          title: OrderDetailPage.rejected,
          text: 'No se cobró nada. Tus productos siguen en el carrito.',
          action: FilledButton(
            onPressed: () => context.go(TiendaRoutes.cart),
            child: const Text('Intentar de nuevo'),
          ),
        ),
      OrderStatus.cancelado => _Banner(
          icon: Icons.cancel_outlined,
          color: AppColors.sosText,
          background: AppColors.sosContainer,
          title: 'Pedido cancelado por la clínica',
          text: [
            if (o.motivoCancelacion case final m? when m.isNotEmpty)
              'Motivo: $m',
            'La clínica se comunicará contigo para el reembolso.',
          ].join('\n'),
        ),
      _ => _Banner(
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          background: AppColors.slotAvailableContainer,
          title: OrderDetailPage.approved,
          text: o.estado == OrderStatus.entregado
              ? 'Pedido entregado. ¡Gracias por tu compra!'
              : 'La clínica ya recibió tu pedido.',
        ),
    };
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.text,
    this.action,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String text;
  final Widget? action;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(text,
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textPrimary)),
            if (busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator()
            ],
            if (action != null) ...[const SizedBox(height: 10), action!],
          ],
        ),
      ),
    );
  }
}

/// pagado → preparando → listo/enviado → entregado.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final s in steps)
          Semantics(
            label: '${s.label}: ${switch (s.state) {
              TimelineStepState.done => 'hecho',
              TimelineStepState.current => 'en curso',
              TimelineStepState.pending => 'pendiente',
            }}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    switch (s.state) {
                      TimelineStepState.done => Icons.check_circle,
                      TimelineStepState.current => Icons.radio_button_checked,
                      TimelineStepState.pending => Icons.radio_button_unchecked,
                    },
                    color: s.state == TimelineStepState.pending
                        ? AppColors.textMuted
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.label,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: s.state == TimelineStepState.current
                            ? FontWeight.w800
                            : null,
                        color: s.state == TimelineStepState.pending
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Escribir a la clínica" (plugin chat, por ruta) y "Llamar".
class _ContactButtons extends ConsumerWidget {
  const _ContactButtons({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone =
        ref.watch(shopClinicProvider(order.clinicId)).value?.telefono ?? '';
    final chat = TiendaRoutes.chatWithClinic(order.clinicId);
    final canChat = ref.watch(pluginRegistryProvider).hasRoute(chat);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (canChat)
          OutlinedButton.icon(
            onPressed: () => context.push(chat),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Escribir a la clínica'),
          ),
        OutlinedButton.icon(
          onPressed: phone.isEmpty
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  var ok = false;
                  try {
                    ok = await ref.read(shopUrlOpenerProvider)(
                      Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
                    );
                  } catch (_) {}
                  if (!ok) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text('No se pudo abrir el teléfono')));
                  }
                },
          icon: const Icon(Icons.call_outlined),
          label: const Text('Llamar'),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
