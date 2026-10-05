import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/domain/app_user.dart';
import '../router/core_routes.dart';
import 'mascoti_plugin.dart';

/// Registro central de plugins (el corazón del microkernel).
class PluginRegistry {
  PluginRegistry(List<MascotiPlugin> plugins)
      : _plugins = List.unmodifiable(plugins) {
    _validate();
  }

  final List<MascotiPlugin> _plugins;

  List<MascotiPlugin> get plugins => _plugins;

  void _validate() {
    final ids = <String>{};
    for (final plugin in _plugins) {
      if (!ids.add(plugin.id)) {
        throw StateError('Plugin duplicado: "${plugin.id}"');
      }
      if (CoreRoutes.all.any((core) => isUnder(core, plugin.basePath))) {
        throw StateError(
          'El plugin "${plugin.id}" usa un prefijo reservado por el core',
        );
      }
      for (final route in plugin.routes()) {
        if (route is GoRoute && !isUnder(route.path, plugin.basePath)) {
          throw StateError(
            'La ruta "${route.path}" del plugin "${plugin.id}" '
            'debe empezar con "${plugin.basePath}"',
          );
        }
      }
    }
  }

  /// true si [location] es [base] o una subruta de [base].
  static bool isUnder(String location, String base) =>
      location == base || location.startsWith('$base/');

  Future<void> initializeAll() async {
    for (final plugin in _plugins) {
      await plugin.initialize();
    }
  }

  bool isEnabled(String pluginId) => _plugins.any((p) => p.id == pluginId);

  List<MascotiPlugin> pluginsFor(UserRole role) =>
      _plugins.where((p) => p.roles.contains(role)).toList();

  List<RouteBase> get routes => [
        for (final plugin in _plugins) ...plugin.routes(),
      ];

  List<PluginDestination> destinationsFor(UserRole role) {
    final list = [
      for (final plugin in pluginsFor(role)) ...plugin.destinations(role),
    ];
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  MascotiPlugin? pluginForLocation(String location) {
    for (final plugin in _plugins) {
      if (isUnder(location, plugin.basePath)) return plugin;
    }
    return null;
  }

  /// true si algún plugin habilitado declara una ruta para [location]
  /// (se ignoran query y fragmento; `:param` acepta cualquier segmento).
  /// Sirve para mostrar como "Próximamente" los accesos a pantallas que
  /// todavía no existen, sin importar el plugin que las aporta.
  bool hasRoute(String location) {
    final target = Uri.parse(location).pathSegments;
    bool matches(String pattern) {
      final parts = Uri.parse(pattern).pathSegments;
      if (parts.length != target.length) return false;
      for (var i = 0; i < parts.length; i++) {
        if (!parts[i].startsWith(':') && parts[i] != target[i]) return false;
      }
      return true;
    }

    bool visit(List<RouteBase> routes, String parent) {
      for (final route in routes) {
        var base = parent;
        if (route is GoRoute) {
          base = route.path.startsWith('/')
              ? route.path
              : '${parent == '/' ? '' : parent}/${route.path}';
          if (matches(base)) return true;
        }
        if (visit(route.routes, base)) return true;
      }
      return false;
    }

    return _plugins.any((plugin) => visit(plugin.routes(), '/'));
  }

  /// Pantalla inicial de un rol: su primera pestaña, o /inicio si no hay.
  String homeFor(UserRole role) {
    final destinations = destinationsFor(role);
    return destinations.isEmpty ? CoreRoutes.home : destinations.first.path;
  }
}

/// Se sobrescribe en main.dart con el registro real.
final pluginRegistryProvider = Provider<PluginRegistry>(
  (ref) => throw UnimplementedError('pluginRegistryProvider se define en main.dart'),
);
