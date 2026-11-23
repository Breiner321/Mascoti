import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/domain/order.dart';
import '../../domain/clinic_order_rules.dart';
import '../../tienda_routes.dart';
import '../comun/shop_message.dart';
import 'clinic_order_card.dart';

/// Pedidos recibidos por la clínica (`/tienda/clinica/pedidos`, RF-07):
/// pestañas "Por preparar", "Listos o enviados" e "Historial" en tiempo
/// real, cada una con su número de pedidos. Destino de la notificación
/// "Nuevo pedido".
class ClinicOrdersPage extends ConsumerWidget {
  const ClinicOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId;
    final orders = clinicId == null ? null : ref.watch(clinicOrdersProvider(clinicId));
    final list = orders?.value ?? const <ShopOrder>[];

    return DefaultTabController(
      length: ClinicOrderTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pedidos'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final tab in ClinicOrderTab.values)
                Tab(text: '${tab.label} (${tab.select(list).length})'),
            ],
          ),
        ),
        body: SafeArea(
          child: switch (orders) {
            null => const ShopMessage(
                icon: Icons.store_outlined,
                text: 'Tu cuenta no tiene una clínica asociada.',
              ),
            AsyncData() => TabBarView(
                children: [
                  for (final tab in ClinicOrderTab.values) _OrdersList(tab: tab, orders: list),
                ],
              ),
            AsyncError() => ShopMessage(
                icon: Icons.cloud_off,
                text: 'No se pudieron cargar los pedidos.',
                action: FilledButton(
                  onPressed: () => ref.invalidate(clinicOrdersProvider(clinicId!)),
                  child: const Text('Reintentar'),
                ),
              ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.tab, required this.orders});

  final ClinicOrderTab tab;
  final List<ShopOrder> orders;

  @override
  Widget build(BuildContext context) {
    final selected = tab.select(orders);
    if (selected.isEmpty) {
      return ShopMessage(
        icon: Icons.receipt_long_outlined,
        text: switch (tab) {
          ClinicOrderTab.porPreparar => 'No tienes pedidos por preparar.',
          ClinicOrderTab.listos => 'No tienes pedidos listos o enviados.',
          ClinicOrderTab.historial => 'Aún no hay pedidos entregados o cancelados.',
        },
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: selected.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final order = selected[i];
        return ClinicOrderCard(
          key: ValueKey(order.id),
          order: order,
          onTap: () => context.push(TiendaRoutes.clinicOrder(order.id)),
        );
      },
    );
  }
}
