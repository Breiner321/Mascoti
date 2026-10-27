import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de accesibilidad del dispositivo (Cambio 3). Se guardan en el
/// teléfono, no en la cuenta: cada dispositivo puede tener las suyas.
@immutable
class AccessibilitySettings {
  const AccessibilitySettings({
    this.themeMode = ThemeMode.system,
    this.highContrast = false,
    this.textScale = 1.0,
    this.reduceMotion = false,
  });

  /// Claro (diseño de los mockups), oscuro o según el sistema.
  final ThemeMode themeMode;
  final bool highContrast;

  /// Tamaño de texto de la app; se multiplica por el del sistema.
  final double textScale;

  /// Desactiva animaciones además de lo que diga el sistema.
  final bool reduceMotion;

  /// Opciones de tamaño que ofrece la pantalla "Accesibilidad".
  static const textScaleOptions = [1.0, 1.15, 1.3, 1.5];

  /// Tope del tamaño combinado (sistema × app): el rango que se prueba.
  static const maxTextScale = 2.0;

  AccessibilitySettings copyWith({
    ThemeMode? themeMode,
    bool? highContrast,
    double? textScale,
    bool? reduceMotion,
  }) =>
      AccessibilitySettings(
        themeMode: themeMode ?? this.themeMode,
        highContrast: highContrast ?? this.highContrast,
        textScale: textScale ?? this.textScale,
        reduceMotion: reduceMotion ?? this.reduceMotion,
      );

  @override
  bool operator ==(Object other) =>
      other is AccessibilitySettings &&
      other.themeMode == themeMode &&
      other.highContrast == highContrast &&
      other.textScale == textScale &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(themeMode, highContrast, textScale, reduceMotion);

  @override
  String toString() =>
      'AccessibilitySettings(tema: ${themeMode.name}, altoContraste: $highContrast, '
      'texto: $textScale, reducirAnimaciones: $reduceMotion)';
}

/// Lee y guarda [AccessibilitySettings] en SharedPreferences.
class AccessibilitySettingsNotifier extends Notifier<AccessibilitySettings> {
  static const _theme = 'a11y.tema';
  static const _contrast = 'a11y.altoContraste';
  static const _scale = 'a11y.tamanoTexto';
  static const _motion = 'a11y.reducirAnimaciones';

  /// El usuario ya cambió algo: la carga inicial (asíncrona) no lo pisa.
  bool _changedByUser = false;

  @override
  AccessibilitySettings build() {
    _load();
    return const AccessibilitySettings();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_changedByUser) return;
      state = AccessibilitySettings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == p.getString(_theme),
          orElse: () => ThemeMode.system,
        ),
        highContrast: p.getBool(_contrast) ?? false,
        textScale: p.getDouble(_scale) ?? 1.0,
        reduceMotion: p.getBool(_motion) ?? false,
      );
    } catch (_) {
      // Sin almacenamiento disponible: valores por defecto.
    }
  }

  /// Aplica [change] sobre el estado ACTUAL (no sobre uno capturado antes,
  /// para no perder un cambio hecho justo antes).
  Future<void> change(AccessibilitySettings Function(AccessibilitySettings) change) =>
      update(change(state));

  Future<void> update(AccessibilitySettings next) async {
    _changedByUser = true;
    state = next;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_theme, next.themeMode.name);
      await p.setBool(_contrast, next.highContrast);
      await p.setDouble(_scale, next.textScale);
      await p.setBool(_motion, next.reduceMotion);
    } catch (_) {
      // La preferencia aplica en esta sesión aunque no se pueda guardar.
    }
  }
}

final accessibilitySettingsProvider =
    NotifierProvider<AccessibilitySettingsNotifier, AccessibilitySettings>(
  AccessibilitySettingsNotifier.new,
);
