import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/shop_providers.dart';
import '../../../../core/domain/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/cart_rules.dart';
import '../clinica/product_thumbnail.dart';
import '../comun/price_format.dart';
import '../comun/shop_message.dart';
import 'add_to_cart.dart';

/// Detalle de un producto para el dueño (`/tienda/producto/:id?clinicId=…`,
/// RF-12): foto, precio, descripción, cantidad (máximo lo disponible) y
/// "Agregar al carrito".
class ProductPage extends ConsumerStatefulWidget {
  const ProductPage({super.key, required this.productId, this.clinicId});

  final String productId;
  final String? clinicId;

  @override
  ConsumerState<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends ConsumerState<ProductPage> {
  int _cantidad = 1;
  bool _adding = false;

  Future<void> _add(Product product) async {
    setState(() => _adding = true);
    final ok = await addProductToCart(
        context, ref, product, clampQuantity(_cantidad, product));
    if (mounted) {
      setState(() {
        _adding = false;
        if (ok) _cantidad = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = widget.clinicId;
    Widget scaffold(Widget body) =>
        Scaffold(appBar: AppBar(title: const Text('Producto')), body: body);
    if (clinicId == null) {
      return scaffold(const ShopMessage(
          icon: Icons.search_off, text: 'No encontramos este producto.'));
    }
    final query = (clinicId: clinicId, productId: widget.productId);
    // Se escucha el carrito para saber de qué clínica es al agregar.
    ref.watch(cartProvider);
    final product = ref.watch(productProvider(query));
    return switch (product) {
      AsyncValue(value: final Product p) when p.isVisibleToOwners =>
        scaffold(_body(p)),
      AsyncData() => scaffold(const ShopMessage(
          icon: Icons.search_off,
          text: 'Este producto ya no está disponible.',
        )),
      AsyncError() => scaffold(ShopMessage(
          icon: Icons.cloud_off,
          text: 'No pudimos cargar el producto.',
          action: FilledButton(
            onPressed: () => ref.invalidate(productProvider(query)),
            child: const Text('Reintentar'),
          ),
        )),
      _ => scaffold(const Center(child: CircularProgressIndicator())),
    };
  }

  Widget _body(Product p) {
    final textTheme = Theme.of(context).textTheme;
    final top = maxQuantity(p);
    final soldOut = top == 0;
    final cantidad = soldOut ? 0 : _cantidad.clamp(1, top);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: LayoutBuilder(
            builder: (context, c) => ProductThumbnail(
              photoPath: p.fotoPath,
              name: p.nombre,
              size: c.maxWidth.clamp(0, 320).toDouble(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(p.categoria.label,
            style: textTheme.labelLarge?.copyWith(color: AppColors.textMuted)),
        Text(p.nombre,
            style:
                textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          formatCop(p.precio),
          style: textTheme.titleLarge
              ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          soldOut
              ? 'Agotado'
              : top == 1
                  ? 'Queda 1 unidad'
                  : 'Disponibles: ${p.available}',
          style: textTheme.bodyMedium?.copyWith(
            color: soldOut ? AppColors.sosText : AppColors.textMuted,
            fontWeight: soldOut ? FontWeight.w700 : null,
          ),
        ),
        if (p.descripcion.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(p.descripcion.trim(), style: textTheme.bodyMedium),
        ],
        const SizedBox(height: 24),
        if (soldOut)
          const Text('Este producto está agotado. Vuelve a revisar más tarde.')
        else ...[
          Row(
            children: [
              Text('Cantidad', style: textTheme.titleSmall),
              const Spacer(),
              QuantitySelector(
                value: cantidad,
                max: top,
                productName: p.nombre,
                onChanged: (v) => setState(() => _cantidad = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _adding ? null : () => _add(p),
            icon: _adding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_shopping_cart),
            label: const Text('Agregar al carrito'),
          ),
        ],
      ],
    );
  }
}
