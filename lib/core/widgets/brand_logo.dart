import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Logo provisional de Mascoti (huella), hasta tener el archivo definitivo.
/// [BrandLogo.mark] es el cuadro de la bienvenida y [BrandLogo.wordmark] el
/// del encabezado (mockups: cuadro "LOGO").
class BrandLogo extends StatelessWidget {
  const BrandLogo.mark({super.key, this.size = 96}) : _wordmark = false;

  const BrandLogo.wordmark({super.key}) : size = 36, _wordmark = true;

  final double size;
  final bool _wordmark;

  @override
  Widget build(BuildContext context) {
    if (!_wordmark) {
      return Semantics(
        label: 'Mascoti',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(size / 4),
            border: Border.all(color: AppColors.primarySoft, width: 2),
          ),
          child: Icon(Icons.pets, size: size / 2, color: AppColors.primary),
        ),
      );
    }
    return Container(
      height: size,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pets, size: 18, color: AppColors.primary),
          SizedBox(width: 6),
          Text(
            'Mascoti',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
