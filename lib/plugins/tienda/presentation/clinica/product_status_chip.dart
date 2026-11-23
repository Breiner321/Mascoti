import 'package:flutter/material.dart';

import '../../../../core/domain/product.dart';
import '../../../../core/theme/app_theme.dart';
import 'status_pill.dart';

/// Estado del producto con ícono y texto (no solo color): Activo, Agotado
/// o Inactivo.
class ProductStatusChip extends StatelessWidget {
  const ProductStatusChip({super.key, required this.status});

  final ProductStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      ProductStatus.activo => (Icons.check_circle_outline, AppColors.success),
      ProductStatus.agotado => (Icons.remove_shopping_cart_outlined, AppColors.sosText),
      ProductStatus.inactivo => (Icons.visibility_off_outlined, AppColors.textMuted),
    };
    return StatusPill(icon: icon, color: color, label: status.label);
  }
}
