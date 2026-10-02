import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../auth/domain/app_user.dart';

/// Pestaña que un plugin aporta a la barra de navegación inferior.
@immutable
class PluginDestination {
  const PluginDestination({
    required this.label,
    required this.icon,
    required this.path,
    this.selectedIcon,
    this.order = 100,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;

  /// Ruta a la que navega la pestaña (debe pertenecer al plugin).
  final String path;

  /// Menor = más a la izquierda. La primera pestaña es el "home" del rol.
  final int order;
}

/// Contrato que todo módulo funcional de Mascoti debe implementar.
///
/// Reglas (ver docs/arquitectura.md):
/// - Un plugin NO importa otro plugin.
/// - Todas sus rutas de primer nivel empiezan con [basePath].
/// - Se registra únicamente en `plugin_manifest.dart`.
abstract class MascotiPlugin {
  const MascotiPlugin();

  /// Identificador único, en minúsculas. Define el prefijo de rutas.
  String get id;

  /// Roles que pueden ver y navegar este plugin.
  Set<UserRole> get roles;

  String get basePath => '/$id';

  /// Rutas go_router del plugin. Se montan dentro del AppShell.
  List<RouteBase> routes();

  /// Pestañas de la barra inferior que el plugin aporta para [role].
  List<PluginDestination> destinations(UserRole role) => const [];

  /// Paso obligatorio para [user] (onboarding, perfil incompleto…): una ruta
  /// del plugin a la que el router lo lleva sí o sí hasta que el valor vuelva
  /// a ser null. Debe devolver siempre el mismo provider para el mismo usuario
  /// (p. ej. un `family`). Por defecto el plugin no exige nada.
  ProviderListenable<AsyncValue<String?>>? requiredStep(AppUser user) => null;

  /// Configuración opcional al arrancar la app (se ejecuta una vez).
  Future<void> initialize() async {}
}
