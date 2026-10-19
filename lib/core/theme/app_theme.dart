import 'package:flutter/material.dart';

/// Colores tomados de docs/mockups/mockups_Mascoti.pdf.
abstract final class AppColors {
  static const primary =
      Color(0xFF7E22CE); // morado principal (encabezado, botones)
  static const primaryLight = Color(0xFF9346D6);
  static const primaryContainer = Color(0xFFF3E8FF); // tarjetas y chips
  static const primarySoft =
      Color(0xFFE9D5FF); // botón deshabilitado ("Continuar")
  static const background = Color(0xFFFAF5FF); // fondo general
  static const surface = Color(0xFFFFFFFF); // tarjetas y botones blancos
  static const border = Color(0xFFEDE4F7); // borde de tarjetas
  static const textPrimary = Color(0xFF1E1530); // títulos
  static const onPrimary = Color(0xFFFFFFFF); // texto sobre morado o rojo
  static const onPrimaryTranslucent =
      Color(0x29FFFFFF); // botones del encabezado
  static const sos = Color(0xFFDC2626); // botón SOS / emergencia
  static const sosContainer = Color(0xFFFEF2F2); // tarjeta "Emergencia"
  static const sosBorder = Color(0xFFFECACA);
  static const success = Color(0xFF16A34A); // snackbar "Perfil actualizado"
  static const textMuted = Color(0xFF81778C);

  // Directorio (RF-09): punto azul de "estás aquí" en el mapa.
  static const mapUser = Color(0xFF2563EB);

  // Agenda (RF-06): estados de las franjas.
  static const slotAvailable = success; // disponible
  static const slotAvailableContainer = Color(0xFFDCFCE7);
  static const slotCovered =
      Color(0xFFF0FDF4); // cubierta por un servicio largo
  static const slotBlocked = Color(0xFFB45309); // no disponible (almuerzo…)
  static const slotBlockedContainer = Color(0xFFFEF3C7);
  static const slotLocked = Color(0xFF6B7280); // ocupada / reservada
  static const slotLockedContainer = Color(0xFFE5E7EB);
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      primaryContainer: AppColors.primaryContainer,
      error: AppColors.sos,
      surface: AppColors.surface,
      onPrimary: AppColors.onPrimary,
      onSurface: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          // Mockup LOGIN: deshabilitado = morado claro con texto morado.
          disabledBackgroundColor: AppColors.primarySoft,
          disabledForegroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryContainer,
      ),
    );
  }
}
