import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../auth/domain/app_user.dart';
import '../kernel/mascoti_plugin.dart';
import '../kernel/plugin_registry.dart';
import '../notificaciones/presentation/notification_bell.dart';
import '../router/core_routes.dart';
import '../theme/app_theme.dart';
import 'brand_logo.dart';
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
      appBar: _ShellHeader(
        // Carrito y SOS solo para el dueño y solo si su plugin está activo.
        showCart: isOwner && registry.isEnabled('tienda'),
        showSos: isOwner && registry.isEnabled('sos'),
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
                    icon: _BadgedIcon(icon: d.icon, badge: d.badge),
                    selectedIcon: _BadgedIcon(icon: d.selectedIcon ?? d.icon, badge: d.badge),
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

/// Encabezado morado de los mockups: logo a la izquierda; carrito, SOS,
/// notificaciones (RF-13) y perfil a la derecha. El perfil no está en el mockup, pero es el único
/// camino a "Cerrar sesión" (RF-03).
class _ShellHeader extends StatelessWidget implements PreferredSizeWidget {
  const _ShellHeader({required this.showCart, required this.showSos});

  final bool showCart;
  final bool showSos;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const BrandLogo.wordmark(),
                const Spacer(),
                if (showCart)
                  _HeaderButton(
                    tooltip: 'Carrito',
                    icon: Icons.shopping_cart_outlined,
                    onPressed: () => context.push('/tienda/carrito'),
                  ),
                if (showSos) const SosButton(),
                const NotificationBell(),
                _HeaderButton(
                  tooltip: 'Perfil',
                  icon: Icons.account_circle_outlined,
                  onPressed: () => context.go(CoreRoutes.profile),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón cuadrado translúcido del encabezado (carrito, perfil).
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.onPrimaryTranslucent,
          foregroundColor: AppColors.onPrimary,
          fixedSize: const Size(40, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// Ícono de una pestaña con el contador opcional del plugin.
class _BadgedIcon extends ConsumerWidget {
  const _BadgedIcon({required this.icon, required this.badge});

  final IconData icon;
  final ProviderListenable<int>? badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = badge;
    final count = source == null ? 0 : ref.watch(source);
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(icon),
    );
  }
}
