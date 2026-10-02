import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../auth/domain/app_user.dart';
import '../kernel/mascoti_plugin.dart';
import '../kernel/plugin_registry.dart';
import '../router/core_routes.dart';
import '../theme/app_theme.dart';
import 'sos_button.dart';

/// Estructura común de la app con sesión: encabezado morado + barra inferior
/// armada con las pestañas que aportan los plugins del rol actual.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final registry = ref.watch(pluginRegistryProvider);
    final destinations = registry.destinationsFor(user.role);
    final selected = _selectedIndex(destinations);
    final isOwner = user.role == UserRole.dueno;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Mascoti', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (isOwner && registry.isEnabled('tienda'))
            IconButton(
              tooltip: 'Carrito',
              icon: const Icon(Icons.shopping_cart_outlined),
              onPressed: () => context.push('/tienda/carrito'),
            ),
          if (isOwner && registry.isEnabled('sos')) const SosButton(),
          IconButton(
            tooltip: 'Perfil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.go(CoreRoutes.profile),
          ),
        ],
      ),
      body: SafeArea(child: child),
      // NavigationBar necesita al menos 2 pestañas.
      bottomNavigationBar: destinations.length < 2
          ? null
          : NavigationBar(
              selectedIndex: selected < 0 ? 0 : selected,
              onDestinationSelected: (i) => context.go(destinations[i].path),
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon ?? d.icon),
                    label: d.label,
                  ),
              ],
            ),
    );
  }

  /// Pestaña cuya ruta coincide con la ubicación actual (la más específica).
  int _selectedIndex(List<PluginDestination> destinations) {
    var best = -1;
    var bestLength = -1;
    for (var i = 0; i < destinations.length; i++) {
      final path = destinations[i].path;
      if (PluginRegistry.isUnder(location, path) && path.length > bestLength) {
        best = i;
        bestLength = path.length;
      }
    }
    return best;
  }
}
