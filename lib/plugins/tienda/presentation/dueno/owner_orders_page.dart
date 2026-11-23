import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/domain/order.dart';
import '../../../../core/format/bogota_time.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/cart_rules.dart';
import '../../tienda_routes.dart';
import '../clinica/order_status_chip.dart';
import '../comun/price_format.dart';
import '../comun/shop_message.dart';
import 'owner_shop_providers.dart';

/// "Mis pedidos" del dueño (`/tienda/pedidos`, RF-12): Activos e Historial,
/// en tiempo real.
class OwnerOrdersPage extends ConsumerWidget {
  const OwnerOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final orders = ref.watch(ownerOrdersProvider(uid));
    final now = ref.read(shopClockProvider)();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis pedidos'),
          bottom: const TabBar(
              tabs: [Tab(text: 'Activos'), Tab(text: 'Historial')]),
        ),
        body: switch (orders) {
          AsyncData(:final value) => TabBarView(
              children: [
                _OrdersList(
                  orders: [
                    for (final o in value)
                      if (isActiveOrder(o, now)) o
                  ],
                  empty: 'No tienes pedidos en curso.',
                ),
                _OrdersList(
                  orders: [
                    for (final o in value)
                      if (!isActiveOrder(o, now)) o
                  ],
                  empty: 'Aún no tienes pedidos anteriores.',
                ),
              ],
            ),
          AsyncError() => ShopMessage(
              icon: Icons.cloud_off,
              text: 'No pudimos cargar tus pedidos.',
              action: FilledButton(
                onPressed: () => ref.invalidate(ownerOrdersProvider(uid)),
                child: const Text('Reintentar'),
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.orders, required this.empty});

  final List<ShopOrder> orders;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return ShopMessage(
        icon: Icons.receipt_long_outlined,
        text: empty,
        action: OutlinedButton(
          onPressed: () => context.go(TiendaRoutes.store),
          child: const Text('Ir a la tienda'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _OrderCard(order: orders[i]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final ShopOrder order;

  static const _months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sept',
    'oct',
    'nov',
    'dic'
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final o = order;
    final created = o.createdAt;
    final date = created == null
        ? ''
        : () {
            final w = BogotaTime.wallClock(created);
            return '${w.day} ${_months[w.month - 1]}';
          }();
    final units = o.units == 1 ? '1 producto' : '${o.units} productos';
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(TiendaRoutes.order(o.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(o.clinicNombre,
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  OrderStatusChip(status: o.estado),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [if (date.isNotEmpty) date, units, formatCop(o.total)]
                    .join(' · '),
                style:
                    textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
