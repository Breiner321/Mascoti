import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

/// Botón rojo "SOS" del encabezado (mockups). Abre el plugin `sos` (RF-10).
class SosButton extends StatelessWidget {
  const SosButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.sos,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () => context.push('/sos'),
        icon: const Icon(Icons.warning_amber_rounded, size: 18),
        label: const Text('SOS', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
