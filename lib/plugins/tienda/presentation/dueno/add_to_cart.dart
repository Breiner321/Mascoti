import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/offline_write.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/data/shop_repository.dart';
import '../../../../core/domain/cart_item.dart';
import '../../../../core/domain/product.dart';
import '../../domain/cart_rules.dart';
import '../../tienda_routes.dart';
import 'owner_shop_providers.dart';

/// Agrega [cantidad] de [product] al carrito (RF-12). Si el carrito tiene
/// productos de otra clínica pregunta si vaciarlo. Devuelve true si se agregó.
Future<bool> addProductToCart(
  BuildContext context,
  WidgetRef ref,
  Product product,
  int cantidad,
) async {
  final uid = ref.read(currentUserProvider)?.uid;
  if (uid == null) return false;
  final repo = ref.read(shopRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);

  void added() => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('${product.nombre} se agregó al carrito'),
      action: SnackBarAction(
          label: 'Ver carrito',
          onPressed: () => router.push(TiendaRoutes.cart)),
    ));

  // Sin conexión Firestore deja el cambio en cola y su Future no termina:
  // se avisa en vez de dejar el botón girando.
  void queued() => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text(offlineWriteMessage)));

  try {
    if (await awaitWrite(repo.addToCart(uid, product, cantidad, replaceOtherClinic: false))) {
      added();
    } else {
      queued();
    }
    return true;
  } on CartFromOtherClinic {
    // Las pantallas que agregan (catálogo y producto) escuchan el carrito.
    final cart = ref.read(cartProvider).value ?? const <CartItem>[];
    final otherId = cart.isEmpty ? null : cart.first.clinicId;
    final otherName = otherId == null
        ? ''
        : ref.read(visitedClinicsProvider)[otherId] ??
            ref.read(shopClinicProvider(otherId)).value?.nombre ??
            '';
    if (!context.mounted) return false;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Carrito de otra clínica'),
        content: Text(otherClinicQuestion(otherName)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Vaciar y agregar'),
          ),
        ],
      ),
    );
    if (replace != true) return false;
    try {
      if (await awaitWrite(repo.addToCart(uid, product, cantidad, replaceOtherClinic: true))) {
        added();
      } else {
        queued();
      }
      return true;
    } on ShopFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  } on ShopFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo agregar. Intenta de nuevo.')));
  }
  return false;
}

/// Selector de cantidad con botones de 48 dp y etiquetas para TalkBack.
class QuantitySelector extends StatelessWidget {
  const QuantitySelector({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 1,
    this.productName,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String? productName;

  @override
  Widget build(BuildContext context) {
    final of = productName == null ? '' : ' de $productName';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'Disminuir cantidad$of',
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Semantics(
          label: 'Cantidad$of: $value',
          liveRegion: true,
          excludeSemantics: true,
          child: SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Aumentar cantidad$of',
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
