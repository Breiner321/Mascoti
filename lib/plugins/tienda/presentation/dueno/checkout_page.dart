import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/data/shop_repository.dart';
import '../../../../core/domain/order.dart';
import '../../../../core/places/place_address.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/address_autocomplete_field.dart';
import '../../domain/cart_rules.dart';
import '../../tienda_routes.dart';
import '../comun/price_format.dart';
import '../comun/shop_message.dart';
import 'owner_shop_providers.dart';

/// Confirmar la compra (`/tienda/checkout`, RF-12): tipo de entrega,
/// dirección (campo del core) y teléfono, resumen y "Pagar".
///
/// "Pagar" llama a `crear-pedido`, que calcula el total y aparta el stock.
/// Con pagos simulados abre la pantalla de pago de prueba; con Wompi, su
/// Web Checkout en un WebView. El pago lo confirma SOLO el servidor.
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(
      text: ref.read(currentUserProvider)?.telefono ?? '');
  final _details = TextEditingController();
  DeliveryType _tipo = DeliveryType.recoger;
  PlaceAddress? _address;
  bool _paying = false;

  @override
  void dispose() {
    _phone.dispose();
    _details.dispose();
    super.dispose();
  }

  String? get _direccion {
    final base = _address?.direccion;
    if (base == null) return null;
    final extra = _details.text.trim();
    return extra.isEmpty ? base : '$base, $extra';
  }

  Future<void> _pay(String clinicId) async {
    if (!_formKey.currentState!.validate()) return;
    final delivery = OrderDelivery(
      tipo: _tipo,
      telefono: _phone.text.trim(),
      direccion: _tipo == DeliveryType.domicilio ? _direccion : null,
    );
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _paying = true);
    try {
      final session = await ref
          .read(shopRepositoryProvider)
          .createOrder(clinicId: clinicId, delivery: delivery);
      if (session.isSimulated || session.checkoutUrl == null) {
        router.pushReplacement(TiendaRoutes.payOrder(session.orderId));
      } else {
        router.pushReplacement(
          TiendaRoutes.wompiCheckout(session.orderId),
          extra: (
            checkoutUrl: session.checkoutUrl!,
            redirectUrl: session.redirectUrl ?? ''
          ),
        );
      }
    } on ShopFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo crear el pedido. Intenta de nuevo.')));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider).value;
    Widget scaffold(Widget body) => Scaffold(
        appBar: AppBar(title: const Text('Confirmar compra')), body: body);
    if (cart == null) {
      return scaffold(const Center(child: CircularProgressIndicator()));
    }
    if (cart.isEmpty) {
      return scaffold(ShopMessage(
        icon: Icons.shopping_cart_outlined,
        text: 'Tu carrito está vacío.',
        action: FilledButton(
          onPressed: () => context.go(TiendaRoutes.store),
          child: const Text('Ir a la tienda'),
        ),
      ));
    }
    final textTheme = Theme.of(context).textTheme;
    final clinicId = cart.first.clinicId;
    final clinic = ref.watch(shopClinicProvider(clinicId)).value;

    return scaffold(Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Semantics(
            header: true,
            child: Text('Entrega',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          RadioGroup<DeliveryType>(
            groupValue: _tipo,
            onChanged: (v) {
              if (!_paying && v != null) setState(() => _tipo = v);
            },
            child: Column(
              children: [
                for (final t in DeliveryType.values)
                  RadioListTile<DeliveryType>(
                    value: t,
                    enabled: !_paying,
                    title: Text(t.label),
                    subtitle: t == DeliveryType.recoger && clinic != null
                        ? Text(clinic.direccion)
                        : null,
                  ),
              ],
            ),
          ),
          if (_tipo == DeliveryType.domicilio) ...[
            const SizedBox(height: 8),
            AddressAutocompleteField(
              label: 'Dirección de entrega',
              enabled: !_paying,
              onChanged: (a) => setState(() => _address = a),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _details,
              enabled: !_paying,
              maxLength: 60,
              decoration: const InputDecoration(
                  labelText: 'Apartamento, torre o indicaciones (opcional)'),
            ),
          ],
          const SizedBox(height: 8),
          TextFormField(
            controller: _phone,
            enabled: !_paying,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Teléfono de contacto', hintText: '10 dígitos'),
            validator: (v) => RegExp(r'^\d{10}$').hasMatch(v?.trim() ?? '')
                ? null
                : 'El teléfono debe tener 10 dígitos',
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text('Resumen',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (clinic != null) Text(clinic.nombre, style: textTheme.bodyMedium),
          const SizedBox(height: 8),
          for (final item in cart)
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
              Expanded(
                  child:
                      Text('Total de referencia', style: textTheme.titleSmall)),
              Text(formatCop(referenceSubtotal(cart)),
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'El total final lo calcula el servidor con los precios y el stock de hoy. '
            'Tus productos quedan apartados 15 minutos mientras pagas.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          if (_tipo == DeliveryType.domicilio && _address == null) ...[
            const SizedBox(height: 8),
            Text(
              'Elige la dirección de entrega de la lista.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.sosText),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed:
                _paying || (_tipo == DeliveryType.domicilio && _address == null)
                    ? null
                    : () => _pay(clinicId),
            icon: _paying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_outline),
            label: const Text('Pagar'),
          ),
        ],
      ),
    ));
  }
}
