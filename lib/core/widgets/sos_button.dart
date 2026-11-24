import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

/// Botón rojo "SOS" del encabezado (mockups). Abre el plugin `sos` (RF-10).
///
/// Cambio 3: área táctil de 48 dp, ícono y texto (no solo color). El lector
/// de pantalla lo anuncia primero en el encabezado como "Emergencia, botón"
/// (RF-10; el "botón" lo agrega TalkBack).
class SosButton extends StatelessWidget {
  const SosButton({super.key});

  static const semanticLabel = 'Emergencia';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.sos,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => context.push('/sos'),
        icon: const Icon(Icons.warning_amber_rounded, size: 20),
        label: const Text(
          'SOS',
          semanticsLabel: semanticLabel,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
    );
  }
}
