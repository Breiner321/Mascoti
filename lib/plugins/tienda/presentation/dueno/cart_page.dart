import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/data/shop_repository.dart';
import '../../../../core/domain/cart_item.dart';
import '../../../../core/domain/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/cart_rules.dart';
import '../../tienda_routes.dart';
import '../comun/price_format.dart';
import '../comun/shop_message.dart';
import 'add_to_cart.dart';
import 'owner_shop_providers.dart';

/// Carrito del dueño (`/tienda/carrito`, ícono del encabezado, RF-12):
/// cantidades editables, avisos si algo se agotó o cambió de precio y un
/// subtotal de referencia (el total real lo calcula el servidor al pagar).
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  static const referenceNote =
      'Total de referencia. El valor final lo calcula la clínica al confirmar tu compra.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Carrito')),
      body: switch (cart) {
        AsyncData(:final value) when value.isEmpty => ShopMessage(
            icon: Icons.shopping_cart_outlined,
            text: 'Tu carrito está vacío.',
            action: FilledButton(
              onPressed: () => context.go(TiendaRoutes.store),
              child: const Text('Ir a la tienda'),
            ),
          ),
        AsyncData(:final value) => _CartBody(items: value),
        AsyncError() => ShopMessage(
            icon: Icons.cloud_off,
            text: 'No pudimos cargar tu carrito.',
            action: FilledButton(
              onPressed: () => ref.invalidate(cartProvider),
              child: const Text('Reintentar'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _CartBody extends ConsumerWidget {
  const _CartBody({required this.items});

  final List<CartItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final clinicId = items.first.clinicId;
    final clinicName = ref.watch(visitedClinicsProvider)[clinicId] ??
        ref.watch(shopClinicProvider(clinicId)).value?.nombre ??
        '';
    final current = <String, Product>{};
    final issues = <String, List<CartIssue>>{};
    var loading = false;
    for (final item in items) {
      final p = ref.watch(productProvider(
          (clinicId: item.clinicId, productId: item.productId)));
      if (!p.hasValue) {
        loading = true;
        continue;
      }
      final product = p.value;
      if (product != null) current[item.productId] = product;
      issues[item.productId] = cartIssues(item, product);
    }
    final blocked = checkoutBlocked(issues.values);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              if (clinicName.isNotEmpty)
                Text('Productos de $clinicName',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final item in items)
                _CartLine(
                  key: ValueKey(item.productId),
                  item: item,
                  product: current[item.productId],
                  issues: issues[item.productId] ?? const [],
                ),
            ],
          ),
        ),
        Material(
          color: AppColors.surface,
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child:
                              Text('Subtotal', style: textTheme.titleMedium)),
                      Text(
                        formatCop(referenceSubtotal(items, current: current)),
                        style: textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(CartPage.referenceNote,
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: blocked || loading
                        ? null
                        : () => context.push(TiendaRoutes.checkout),
                    child: const Text('Continuar con la compra'),
                  ),
                  if (blocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Corrige los productos marcados para continuar.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall
                            ?.copyWith(color: AppColors.sosText),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CartLine extends ConsumerWidget {
  const _CartLine(
      {super.key,
      required this.item,
      required this.product,
      required this.issues});

  final CartItem item;
  final Product? product;
  final List<CartIssue> issues;

  Future<void> _set(BuildContext context, WidgetRef ref, int cantidad) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(shopRepositoryProvider)
          .setCartQuantity(uid, item.productId, cantidad, product: product);
    } on ShopFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar el carrito.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final p = product;
    final top = p == null ? item.cantidad : maxQuantity(p);
    final price = p?.precio ?? item.precio;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: issues.any((i) => i.blocksCheckout)
                ? AppColors.sosBorder
                : AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.nombre,
                          style: textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${formatCop(price)} c/u',
                          style: textTheme.bodySmall
                              ?.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar ${item.nombre} del carrito',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _set(context, ref, 0),
                ),
              ],
            ),
            Row(
              children: [
                QuantitySelector(
                  value: item.cantidad,
                  // Si hay menos stock, se deja bajar hasta lo disponible.
                  max: top < item.cantidad ? item.cantidad : top,
                  productName: item.nombre,
                  onChanged: (v) {
                    if (v > item.cantidad && v > top) return;
                    _set(context, ref, v);
                  },
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(formatCop(price * item.cantidad),
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      issue.blocksCheckout
                          ? Icons.error_outline
                          : Icons.info_outline,
                      size: 18,
                      color: issue.blocksCheckout
                          ? AppColors.sosText
                          : AppColors.slotBlocked,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(issue.message, style: textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
