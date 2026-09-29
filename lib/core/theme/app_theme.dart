import 'package:flutter/material.dart';

/// Colores tomados de docs/mockups/mockups_Mascoti.pdf.
abstract final class AppColors {
  static const primary = Color(0xFF7E22CE); // morado principal (encabezado, botones)
  static const primaryLight = Color(0xFF9346D6);
  static const primaryContainer = Color(0xFFF3E8FF); // tarjetas y chips
  static const background = Color(0xFFFAF5FF); // fondo general
  static const sos = Color(0xFFDC2626); // botón SOS / emergencia
  static const success = Color(0xFF16A34A); // snackbar "Perfil actualizado"
  static const textMuted = Color(0xFF81778C);
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      primaryContainer: AppColors.primaryContainer,
      error: AppColors.sos,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primaryContainer,
      ),
    );
  }
}
