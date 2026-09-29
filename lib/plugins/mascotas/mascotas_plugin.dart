import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import 'presentation/owner_home_page.dart';

/// Plugin del dueño: home, mascotas e historial médico (RF-08).
class MascotasPlugin extends MascotiPlugin {
  const MascotasPlugin();

  @override
  String get id => 'mascotas';

  @override
  Set<UserRole> get roles => const {UserRole.dueno};

  @override
  List<RouteBase> routes() => [
        GoRoute(
          path: '/mascotas',
          builder: (context, state) => const OwnerHomePage(),
        ),
      ];

  @override
  List<PluginDestination> destinations(UserRole role) => const [
        PluginDestination(
          label: 'Principal',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          path: '/mascotas',
          order: 0,
        ),
      ];
}
