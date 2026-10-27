import 'package:flutter/material.dart';

import 'app_palette.dart';

export 'app_palette.dart';

/// Colores de la paleta activa (Cambio 3: claro, oscuro y alto contraste).
///
/// Los widgets usan `AppColors.primary` etc. como siempre; los valores salen
/// de [palette], que cambia MascotiApp según las preferencias de
/// accesibilidad y luego reconstruye toda la app. Por eso no son `const`.
abstract final class AppColors {
  /// Paleta activa. Solo la cambia MascotiApp (y las pruebas).
  static AppPalette palette = AppPalette.light;

  static Color get primary => palette.primary;
  static Color get primaryLight => palette.primaryLight;
  static Color get primaryContainer => palette.primaryContainer;
  static Color get primarySoft => palette.primarySoft;
  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get border => palette.border;
  static Color get outline => palette.outline;
  static Color get textPrimary => palette.textPrimary;
  static Color get textMuted => palette.textMuted;
  static Color get onPrimary => palette.onPrimary;
  static Color get onPrimaryTranslucent => palette.onPrimaryTranslucent;
  static Color get sos => palette.sos;
  static Color get sosText => palette.sosText;
  static Color get sosContainer => palette.sosContainer;
  static Color get sosBorder => palette.sosBorder;
  static Color get success => palette.success;
  static Color get mapUser => palette.mapUser;
  static Color get slotAvailable => palette.slotAvailable;
  static Color get slotAvailableContainer => palette.slotAvailableContainer;
  static Color get slotCovered => palette.slotCovered;
  static Color get slotBlocked => palette.slotBlocked;
  static Color get slotBlockedContainer => palette.slotBlockedContainer;
  static Color get slotLocked => palette.slotLocked;
  static Color get slotLockedContainer => palette.slotLockedContainer;
}

abstract final class AppTheme {
  /// Tema de los mockups (paleta clara).
  static ThemeData light() => of(AppPalette.light);

  /// Tema construido con [palette]; también deja [palette] como paleta
  /// activa de [AppColors].
  static ThemeData of(AppPalette palette, {bool reduceMotion = false}) {
    AppColors.palette = palette;
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: palette.brightness,
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      primaryContainer: palette.primaryContainer,
      onPrimaryContainer: palette.textPrimary,
      error: palette.sosText,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textMuted,
      outline: palette.outline,
      outlineVariant: palette.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      // Cambio 3: sin animaciones de página si el usuario las desactivó.
      pageTransitionsTheme: reduceMotion
          ? const PageTransitionsTheme(builders: {
              TargetPlatform.android: _NoTransitionsBuilder(),
              TargetPlatform.iOS: _NoTransitionsBuilder(),
            })
          : null,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          // Mockup LOGIN: deshabilitado = morado claro con texto morado.
          disabledBackgroundColor: palette.primarySoft,
          disabledForegroundColor: palette.primary,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.primary,
          side: BorderSide(color: palette.outline),
          minimumSize: const Size(48, 48),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          minimumSize: const Size(48, 48),
        ),
      ),
      chipTheme: ChipThemeData(side: BorderSide(color: palette.outline)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          // Borde de control: 3:1 contra el fondo (WCAG 1.4.11).
          borderSide: BorderSide(color: palette.outline),
        ),
      ),
      cardTheme: CardThemeData(color: palette.surface),
      dividerColor: palette.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.isDark ? palette.surface : palette.textPrimary,
        contentTextStyle: TextStyle(color: palette.isDark ? palette.textPrimary : palette.surface),
        actionTextColor: palette.isDark ? palette.primary : palette.primarySoft,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.primaryContainer,
      ),
    );
  }
}

/// Cambio de página sin animación ("Reducir animaciones").
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
