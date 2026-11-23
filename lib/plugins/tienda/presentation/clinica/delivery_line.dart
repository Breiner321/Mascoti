import 'package:flutter/material.dart';

import '../../../../core/domain/order.dart';
import '../../../../core/theme/app_theme.dart';

/// Tipo de entrega con la dirección (domicilio) o el teléfono (recoger).
class DeliveryLine extends StatelessWidget {
  const DeliveryLine({super.key, required this.delivery, this.style});

  final OrderDelivery delivery;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final domicilio = delivery.tipo == DeliveryType.domicilio;
    final detail = domicilio ? (delivery.direccion ?? '') : 'Tel. ${delivery.telefono}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          domicilio ? Icons.local_shipping_outlined : Icons.storefront_outlined,
          size: 20,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('${delivery.tipo.label}: $detail', style: style)),
      ],
    );
  }
}
