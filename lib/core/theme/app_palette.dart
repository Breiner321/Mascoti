import 'package:flutter/material.dart';

/// Colores de la app (Cambio 3). La paleta clara es la de los mockups
/// (docs/mockups/mockups_Mascoti.pdf) con los ajustes de contraste WCAG AA;
/// la oscura y las de alto contraste mantienen la identidad morada.
/// test/core/theme/app_palette_test.dart verifica el contraste de todas.
@immutable
class AppPalette {
  const AppPalette({
    required this.name,
    required this.brightness,
    required this.primary,
    required this.primaryLight,
    required this.primaryContainer,
    required this.primarySoft,
    required this.background,
    required this.surface,
    required this.border,
    required this.outline,
    required this.textPrimary,
    required this.textMuted,
    required this.onPrimary,
    required this.sos,
    required this.sosText,
    required this.sosContainer,
    required this.sosBorder,
    required this.success,
    required this.mapUser,
    required this.slotAvailable,
    required this.slotAvailableContainer,
    required this.slotCovered,
    required this.slotBlocked,
    required this.slotBlockedContainer,
    required this.slotLocked,
    required this.slotLockedContainer,
  });

  final String name;
  final Brightness brightness;

  /// Morado principal: encabezado, botones y textos destacados.
  final Color primary;
  final Color primaryLight;

  /// Tarjetas y chips.
  final Color primaryContainer;

  /// Botón deshabilitado ("Continuar").
  final Color primarySoft;

  /// Fondo general.
  final Color background;

  /// Tarjetas y botones blancos.
  final Color surface;

  /// Borde decorativo de tarjetas.
  final Color border;

  /// Borde de controles (campos, chips): 3:1 contra el fondo (WCAG 1.4.11).
  final Color outline;
  final Color textPrimary;
  final Color textMuted;

  /// Texto e íconos sobre [primary], [sos] o [success].
  final Color onPrimary;

  /// Botón SOS / emergencia.
  final Color sos;

  /// Texto rojo sobre fondos claros (4.5:1).
  final Color sosText;
  final Color sosContainer;
  final Color sosBorder;

  /// Avisos de éxito ("Perfil actualizado").
  final Color success;

  /// Punto azul de "estás aquí" en el mapa (RF-09).
  final Color mapUser;

  // Agenda: estados de las franjas.
  final Color slotAvailable;
  final Color slotAvailableContainer;
  final Color slotCovered;
  final Color slotBlocked;
  final Color slotBlockedContainer;
  final Color slotLocked;
  final Color slotLockedContainer;

  /// Botones translúcidos del encabezado.
  Color get onPrimaryTranslucent => onPrimary.withAlpha(0x29);

  bool get isDark => brightness == Brightness.dark;

  /// Diseño de los mockups, con contraste AA.
  static const light = AppPalette(
    name: 'claro',
    brightness: Brightness.light,
    primary: Color(0xFF7E22CE),
    primaryLight: Color(0xFF9346D6),
    primaryContainer: Color(0xFFF3E8FF),
    primarySoft: Color(0xFFE9D5FF),
    background: Color(0xFFFAF5FF),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFEDE4F7),
    outline: Color(0xFF8E80A3),
    textPrimary: Color(0xFF1E1530),
    // Antes #81778C (3.95:1 sobre el fondo): no cumplía AA.
    textMuted: Color(0xFF675F73),
    onPrimary: Color(0xFFFFFFFF),
    sos: Color(0xFFDC2626),
    sosText: Color(0xFFB91C1C),
    sosContainer: Color(0xFFFEF2F2),
    sosBorder: Color(0xFFFECACA),
    // Antes #16A34A (3.30:1 con texto blanco).
    success: Color(0xFF15803D),
    mapUser: Color(0xFF2563EB),
    slotAvailable: Color(0xFF15803D),
    slotAvailableContainer: Color(0xFFDCFCE7),
    slotCovered: Color(0xFFF0FDF4),
    slotBlocked: Color(0xFFB45309),
    slotBlockedContainer: Color(0xFFFEF3C7),
    // Antes #6B7280 (3.90:1 sobre su fondo).
    slotLocked: Color(0xFF4B5563),
    slotLockedContainer: Color(0xFFE5E7EB),
  );

  /// Modo oscuro: mismo morado, más claro para leerse sobre fondo oscuro.
  static const dark = AppPalette(
    name: 'oscuro',
    brightness: Brightness.dark,
    primary: Color(0xFFC084FC),
    primaryLight: Color(0xFFD8B4FE),
    primaryContainer: Color(0xFF3B2556),
    primarySoft: Color(0xFF3A2452),
    background: Color(0xFF14101C),
    surface: Color(0xFF1F1829),
    border: Color(0xFF3A2F4A),
    outline: Color(0xFF8E80A3),
    textPrimary: Color(0xFFF4EFFA),
    textMuted: Color(0xFFB8AFC6),
    onPrimary: Color(0xFF1E1530),
    sos: Color(0xFFF87171),
    sosText: Color(0xFFFCA5A5),
    sosContainer: Color(0xFF3B1518),
    sosBorder: Color(0xFF7F1D1D),
    success: Color(0xFF4ADE80),
    mapUser: Color(0xFF60A5FA),
    slotAvailable: Color(0xFF4ADE80),
    slotAvailableContainer: Color(0xFF12321F),
    slotCovered: Color(0xFF0F2418),
    slotBlocked: Color(0xFFFBBF24),
    slotBlockedContainer: Color(0xFF3A2A08),
    slotLocked: Color(0xFFC9CED6),
    slotLockedContainer: Color(0xFF2C3038),
  );

  /// Claro con más contraste (textos y bordes más oscuros).
  static const lightHighContrast = AppPalette(
    name: 'claro alto contraste',
    brightness: Brightness.light,
    primary: Color(0xFF6B21A8),
    primaryLight: Color(0xFF7E22CE),
    primaryContainer: Color(0xFFF3E8FF),
    primarySoft: Color(0xFFE9D5FF),
    background: Color(0xFFFAF5FF),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFF6B5F7D),
    outline: Color(0xFF4A3F5C),
    textPrimary: Color(0xFF1E1530),
    textMuted: Color(0xFF3D3448),
    onPrimary: Color(0xFFFFFFFF),
    sos: Color(0xFFB91C1C),
    sosText: Color(0xFF991B1B),
    sosContainer: Color(0xFFFEF2F2),
    sosBorder: Color(0xFFB91C1C),
    success: Color(0xFF166534),
    mapUser: Color(0xFF1D4ED8),
    slotAvailable: Color(0xFF166534),
    slotAvailableContainer: Color(0xFFDCFCE7),
    slotCovered: Color(0xFFF0FDF4),
    slotBlocked: Color(0xFF92400E),
    slotBlockedContainer: Color(0xFFFEF3C7),
    slotLocked: Color(0xFF374151),
    slotLockedContainer: Color(0xFFE5E7EB),
  );

  /// Oscuro con más contraste.
  static const darkHighContrast = AppPalette(
    name: 'oscuro alto contraste',
    brightness: Brightness.dark,
    primary: Color(0xFFD8B4FE),
    primaryLight: Color(0xFFE9D5FF),
    primaryContainer: Color(0xFF3B2556),
    primarySoft: Color(0xFF3A2452),
    background: Color(0xFF0B0812),
    surface: Color(0xFF1F1829),
    border: Color(0xFF8E80A3),
    outline: Color(0xFFD3C8E2),
    textPrimary: Color(0xFFFFFFFF),
    textMuted: Color(0xFFE2DAEC),
    onPrimary: Color(0xFF1E1530),
    sos: Color(0xFFFCA5A5),
    sosText: Color(0xFFFECACA),
    sosContainer: Color(0xFF3B1518),
    sosBorder: Color(0xFFFCA5A5),
    success: Color(0xFF86EFAC),
    mapUser: Color(0xFF93C5FD),
    slotAvailable: Color(0xFF86EFAC),
    slotAvailableContainer: Color(0xFF12321F),
    slotCovered: Color(0xFF0F2418),
    slotBlocked: Color(0xFFFCD34D),
    slotBlockedContainer: Color(0xFF3A2A08),
    slotLocked: Color(0xFFE5E7EB),
    slotLockedContainer: Color(0xFF2C3038),
  );

  static const all = [light, dark, lightHighContrast, darkHighContrast];

  static AppPalette resolve({required bool dark, required bool highContrast}) => dark
      ? (highContrast ? darkHighContrast : AppPalette.dark)
      : (highContrast ? lightHighContrast : AppPalette.light);
}
