import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import 'presentation/clinic_agenda_page.dart';
import 'presentation/clinic_services_page.dart';

/// Plugin de la clínica: perfil de atención (RF-04), servicios (RF-05),
/// agenda (RF-06) y registros médicos.
class ClinicaPlugin extends MascotiPlugin {
  const ClinicaPlugin();

  @override
  String get id => 'clinica';

  @override
  Set<UserRole> get roles => const {UserRole.clinica};

  @override
  List<RouteBase> routes() => [
        GoRoute(
          path: '/clinica',
          builder: (context, state) => const ClinicAgendaPage(),
        ),
        GoRoute(
          path: '/clinica/servicios',
          builder: (context, state) => const ClinicServicesPage(),
        ),
      ];

  @override
  List<PluginDestination> destinations(UserRole role) => const [
        PluginDestination(
          label: 'Agenda',
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today,
          path: '/clinica',
          order: 0,
        ),
        PluginDestination(
          label: 'Servicios',
          icon: Icons.medical_services_outlined,
          selectedIcon: Icons.medical_services,
          path: '/clinica/servicios',
          order: 20,
        ),
      ];
}
