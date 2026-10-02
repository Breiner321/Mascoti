import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import 'presentation/appointments_page.dart';

/// Plugin compartido por ambos roles: agendamiento y aprobación de citas (RF-14).
/// Ejemplo de plugin que aporta pestañas distintas según el rol.
class ReservasPlugin extends MascotiPlugin {
  const ReservasPlugin();

  @override
  String get id => 'reservas';

  @override
  Set<UserRole> get roles => const {UserRole.dueno, UserRole.clinica};

  @override
  List<RouteBase> routes() => [
        GoRoute(
          path: '/reservas',
          builder: (context, state) => const AppointmentsPage(),
        ),
      ];

  @override
  List<PluginDestination> destinations(UserRole role) => switch (role) {
        UserRole.dueno => const [
            PluginDestination(
              label: 'Citas',
              icon: Icons.event_outlined,
              selectedIcon: Icons.event,
              path: '/reservas',
              order: 30,
            ),
          ],
        UserRole.clinica => const [
            PluginDestination(
              label: 'Solicitudes',
              icon: Icons.inbox_outlined,
              selectedIcon: Icons.inbox,
              path: '/reservas',
              order: 10,
            ),
          ],
      };
}
