import 'package:flutter/material.dart';

import '../../../../core/domain/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/cart_rules.dart';
import '../clinica/product_thumbnail.dart';
import '../comun/price_format.dart';

/// Producto en la cuadrícula del catálogo (mockup VISTA CLIENTE – Tienda):
/// foto, nombre, precio y "+" para agregar; agotado lleva la etiqueta
/// "Agotado" y no tiene botón. TalkBack lo lee completo:
/// "Concentrado 2 kg, 45.000 pesos, agotado".
class CatalogProductCard extends StatelessWidget {
  const CatalogProductCard({
    super.key,
    required this.product,
    required this.onOpen,
    required this.onAdd,
  });

  final Product product;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final soldOut =
        product.estado == ProductStatus.agotado || product.available == 0;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: productSemantics(product),
            excludeSemantics: true,
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: LayoutBuilder(
                        builder: (context, c) => Stack(
                          children: [
                            ProductThumbnail(
                              photoPath: product.fotoPath,
                              name: product.nombre,
                              size: c.maxWidth,
                            ),
                            if (soldOut)
                              Positioned(
                                left: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.sosContainer,
                                    borderRadius: BorderRadius.circular(999),
                                    border:
                                        Border.all(color: AppColors.sosBorder),
                                  ),
                                  child: Text(
                                    'Agotado',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: AppColors.sosText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      formatCop(product.precio),
                      style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (!soldOut)
                  IconButton.filled(
                    tooltip: 'Agregar ${product.nombre} al carrito',
                    icon: const Icon(Icons.add),
                    onPressed: onAdd,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
