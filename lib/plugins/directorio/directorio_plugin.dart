import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import '../../core/router/navigator_keys.dart';
import 'directorio_routes.dart';
import 'presentation/clinic_public_profile_page.dart';
import 'presentation/directory_page.dart';

/// Plugin del dueño: directorio de clínicas cercanas con mapa (RF-09).
class DirectorioPlugin extends MascotiPlugin {
  const DirectorioPlugin();

  @override
  String get id => 'directorio';

  @override
  Set<UserRole> get roles => const {UserRole.dueno};

  @override
  List<RouteBase> routes() => [
        GoRoute(
          path: DirectorioRoutes.map,
          builder: (context, state) => const DirectoryPage(),
        ),
        // Perfil público a pantalla completa, sin barra inferior.
        GoRoute(
          path: DirectorioRoutes.clinicPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              ClinicPublicProfilePage(clinicId: state.pathParameters['id']!),
        ),
      ];

  /// "Mapa" va entre "Principal" (0) y "Citas" (30), como en el mockup.
  @override
  List<PluginDestination> destinations(UserRole role) => const [
        PluginDestination(
          label: 'Mapa',
          icon: Icons.location_on_outlined,
          selectedIcon: Icons.location_on,
          path: DirectorioRoutes.map,
          order: 10,
        ),
      ];
}
