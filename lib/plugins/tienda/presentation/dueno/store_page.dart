import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/shop_providers.dart';
import '../../../../core/domain/product.dart';
import '../../tienda_routes.dart';
import '../comun/shop_message.dart';
import 'add_to_cart.dart';
import 'catalog_product_card.dart';
import 'clinic_picker_sheet.dart';
import 'owner_shop_providers.dart';

/// Pestaña "Tienda" del dueño (`/tienda`, RF-12, mockup VISTA CLIENTE –
/// Tienda): elegir la clínica y ver su catálogo con buscador, filtros por
/// categoría y cuadrícula de productos.
class StorePage extends ConsumerStatefulWidget {
  const StorePage({super.key});

  static const noClinic = 'Elige una clínica para ver sus productos.';

  @override
  ConsumerState<StorePage> createState() => _StorePageState();
}

class _StorePageState extends ConsumerState<StorePage> {
  final _search = TextEditingController();
  ProductCategory? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// La elegida; si no, la del carrito; si no, la primera de "Tus clínicas".
  String? _clinicId() {
    final selected = ref.watch(selectedShopClinicProvider);
    if (selected != null) return selected;
    final cart = ref.watch(cartProvider).value ?? const [];
    if (cart.isNotEmpty) return cart.first.clinicId;
    final visited = ref.watch(visitedClinicsProvider);
    return visited.isEmpty ? null : visited.keys.first;
  }

  Future<void> _pickClinic() async {
    final id = await showClinicPicker(context);
    if (id != null) ref.read(selectedShopClinicProvider.notifier).select(id);
  }

  List<Product> _filter(List<Product> products) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final p in products)
        if ((_category == null || p.categoria == _category) &&
            (q.isEmpty || p.nombre.toLowerCase().contains(q)))
          p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final clinicId = _clinicId();
    final clinicName = clinicId == null
        ? null
        : ref.watch(visitedClinicsProvider)[clinicId] ??
            ref.watch(shopClinicProvider(clinicId)).value?.nombre;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('Tienda',
                    style: textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: () => context.push(TiendaRoutes.ownerOrders),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Mis pedidos'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: OutlinedButton.icon(
            onPressed: _pickClinic,
            icon: const Icon(Icons.storefront_outlined),
            label: Text(
              clinicId == null
                  ? 'Elegir clínica'
                  : 'Clínica: ${clinicName ?? '…'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (clinicId != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar productos',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              children: [
                for (final c in [null, ...ProductCategory.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c?.label ?? 'Todos'),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ),
              ],
            ),
          ),
        ],
        Expanded(child: clinicId == null ? _noClinic() : _catalog(clinicId)),
      ],
    );
  }

  Widget _noClinic() => ShopMessage(
        icon: Icons.storefront_outlined,
        text: StorePage.noClinic,
        action: FilledButton(
            onPressed: _pickClinic, child: const Text('Elegir clínica')),
      );

  Widget _catalog(String clinicId) {
    final products = ref.watch(clinicProductsProvider(clinicId));
    return switch (products) {
      AsyncData(:final value) when value.isEmpty => const ShopMessage(
          icon: Icons.inventory_2_outlined,
          text: 'Esta clínica aún no tiene productos en su tienda.',
        ),
      AsyncData(:final value) => _grid(_filter(value)),
      AsyncError() => ShopMessage(
          icon: Icons.cloud_off,
          text: 'No pudimos cargar el catálogo. Verifica tu conexión.',
          action: FilledButton(
            onPressed: () => ref.invalidate(clinicProductsProvider(clinicId)),
            child: const Text('Reintentar'),
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _grid(List<Product> products) {
    if (products.isEmpty) {
      return const ShopMessage(
        icon: Icons.search_off,
        text: 'No hay productos con ese filtro.',
      );
    }
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    Widget card(Product p) => CatalogProductCard(
          key: ValueKey(p.id),
          product: p,
          onOpen: () => context.push(TiendaRoutes.product(p.clinicId, p.id)),
          onAdd: () => addProductToCart(context, ref, p, 1),
        );
    // Texto grande (Cambio 3): una columna y cada tarjeta del alto que
    // necesite, sin cortar el texto.
    if (scale > 1.5) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => card(products[i]),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // La tarjeta crece con el texto.
        childAspectRatio: 0.62 / scale.clamp(1, 1.5),
      ),
      itemCount: products.length,
      itemBuilder: (context, i) => card(products[i]),
    );
  }
}
