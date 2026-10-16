import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import '../../core/router/navigator_keys.dart';
import 'clinica_routes.dart';
import 'presentation/clinic_agenda_page.dart';
import 'presentation/clinic_providers.dart';
import 'presentation/clinic_services_page.dart';
import 'presentation/clinic_setup_page.dart';

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
          path: ClinicaRoutes.agenda,
          builder: (context, state) => const ClinicAgendaPage(),
        ),
        GoRoute(
          path: ClinicaRoutes.services,
          builder: (context, state) => const ClinicServicesPage(),
        ),
        // A pantalla completa: sin barra inferior mientras sea obligatoria.
        GoRoute(
          path: ClinicaRoutes.setup,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const ClinicSetupPage(),
        ),
      ];

  @override
  List<PluginDestination> destinations(UserRole role) => const [
        PluginDestination(
          label: 'Agenda',
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today,
          path: ClinicaRoutes.agenda,
          order: 0,
        ),
        PluginDestination(
          label: 'Servicios',
          icon: Icons.medical_services_outlined,
          selectedIcon: Icons.medical_services,
          path: ClinicaRoutes.services,
          order: 20,
        ),
      ];

  /// RF-04: editar el perfil de atención después de la primera configuración.
  @override
  List<PluginProfileLink> profileLinks(AppUser user) => user.clinicId == null
      ? const []
      : const [
          PluginProfileLink(
            label: 'Perfil de atención',
            icon: Icons.tune,
            path: ClinicaRoutes.setup,
          ),
        ];

  @override
  ProviderListenable<AsyncValue<String?>>? requiredStep(AppUser user) {
    final clinicId = user.clinicId;
    return clinicId == null ? null : clinicSetupStepProvider(clinicId);
  }
}
