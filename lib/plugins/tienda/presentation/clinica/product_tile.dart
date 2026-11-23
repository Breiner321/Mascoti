import 'package:flutter/material.dart';

import '../../../../core/domain/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/inventory_rules.dart';
import '../comun/price_format.dart';
import 'product_status_chip.dart';
import 'product_thumbnail.dart';
import 'status_pill.dart';

/// Producto del inventario: foto, nombre, precio, stock, estado, aviso de
/// stock bajo y botones +/− para ajustar el stock sin abrir el formulario.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAdjust,
    this.busy = false,
  });

  final Product product;
  final VoidCallback onTap;

  /// +1 o −1.
  final ValueChanged<int> onAdjust;

  /// true mientras se guarda un ajuste de stock: los botones se desactivan.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lowStock = InventoryRules.isLowStock(product);
    final units = product.stock == 1 ? '1 unidad' : '${product.stock} unidades';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductThumbnail(photoPath: product.fotoPath, name: product.nombre),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.nombre, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${formatCop(product.precio)} · ${product.categoria.label}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ProductStatusChip(status: product.estado),
                        if (lowStock)
                          StatusPill(
                            icon: Icons.warning_amber_rounded,
                            color: AppColors.slotBlocked,
                            label: 'Stock bajo',
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Stock: $units', style: theme.textTheme.bodyMedium),
                        IconButton(
                          tooltip: 'Restar una unidad de ${product.nombre}',
                          onPressed: busy || product.stock == 0 ? null : () => onAdjust(-1),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Sumar una unidad de ${product.nombre}',
                          onPressed: busy || product.stock >= ProductLimits.maxStock
                              ? null
                              : () => onAdjust(1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
