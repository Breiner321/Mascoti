import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/data/shop_repository.dart';
import '../../../../core/domain/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/inventory_rules.dart';
import '../../tienda_routes.dart';
import '../comun/shop_message.dart';
import 'clinic_shop_providers.dart';
import 'product_tile.dart';

/// Pestaña "Inventario" de la clínica (`/tienda/inventario`, RF-07): lista
/// de productos en tiempo real con buscador, filtro por estado, aviso de
/// stock bajo y ajuste rápido del stock (+/−).
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _search = TextEditingController();
  InventoryFilter _filter = InventoryFilter.todos;

  /// Productos con un ajuste de stock en curso.
  final Set<String> _busy = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _adjust(String clinicId, Product product, int delta) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(product.id));
    try {
      await ref.read(shopRepositoryProvider).adjustStock(clinicId, product.id, delta);
    } on ShopFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar el stock. Intenta de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId;
    if (clinicId == null) {
      return const ShopMessage(
        icon: Icons.store_outlined,
        text: 'Tu cuenta no tiene una clínica asociada.',
      );
    }
    final inventory = ref.watch(inventoryProvider(clinicId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(TiendaRoutes.newProduct),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Producto'),
      ),
      body: switch (inventory) {
        AsyncData(:final value) => _buildList(clinicId, value),
        AsyncError() => ShopMessage(
            icon: Icons.cloud_off,
            text: 'No se pudo cargar tu inventario.',
            action: FilledButton(
              onPressed: () => ref.invalidate(inventoryProvider(clinicId)),
              child: const Text('Reintentar'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildList(String clinicId, List<Product> all) {
    if (all.isEmpty) {
      return Column(
        children: [
          const _Header(),
          Expanded(
            child: ShopMessage(
              icon: Icons.inventory_2_outlined,
              text: 'Aún no tienes productos. Agrega el primero',
              action: FilledButton.icon(
                onPressed: () => context.push(TiendaRoutes.newProduct),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo Producto'),
              ),
            ),
          ),
        ],
      );
    }

    final products = InventoryRules.filter(all, query: _search.text, filter: _filter);
    final lowStock = all.where(InventoryRules.isLowStock).length;

    return ListView(
      // Espacio abajo para que el botón flotante no tape el último producto.
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        const _Header(),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Buscar producto',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar búsqueda',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final f in InventoryFilter.values)
              ChoiceChip(
                label: Text(f.label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        if (lowStock > 0) ...[
          const SizedBox(height: 12),
          _LowStockBanner(
            count: lowStock,
            onTap: () => setState(() => _filter = InventoryFilter.stockBajo),
          ),
        ],
        const SizedBox(height: 12),
        if (products.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: ShopMessage(
              icon: Icons.search_off,
              text: 'No hay productos que coincidan con tu búsqueda.',
            ),
          )
        else
          for (final p in products)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ProductTile(
                key: ValueKey(p.id),
                product: p,
                busy: _busy.contains(p.id),
                onTap: () => context.push(TiendaRoutes.editProduct(p.id)),
                onAdjust: (delta) => _adjust(clinicId, p, delta),
              ),
            ),
      ],
    );
  }
}

/// Título y acceso a "Pedidos" con el número de pedidos por preparar.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingClinicOrdersCountProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Text('Inventario', style: Theme.of(context).textTheme.headlineSmall),
          Semantics(
            label: pending == 0 ? null : '$pending por preparar',
            child: OutlinedButton.icon(
              onPressed: () => context.push(TiendaRoutes.clinicOrders),
              icon: Badge(
                isLabelVisible: pending > 0,
                label: Text('$pending'),
                child: const Icon(Icons.receipt_long_outlined),
              ),
              label: const Text('Pedidos'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = count == 1
        ? '1 producto con stock bajo (${InventoryRules.lowStockThreshold} unidades o menos)'
        : '$count productos con stock bajo '
            '(${InventoryRules.lowStockThreshold} unidades o menos)';
    return Material(
      color: AppColors.slotBlockedContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.slotBlocked),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.slotBlocked),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                Text(
                  'Ver',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
