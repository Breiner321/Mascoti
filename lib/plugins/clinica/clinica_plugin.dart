import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import '../../core/router/navigator_keys.dart';
import 'clinica_routes.dart';
import 'presentation/clinic_agenda_page.dart';
import 'presentation/clinic_providers.dart';
import 'presentation/clinic_services_page.dart';
import 'presentation/clinic_setup_page.dart';
import 'presentation/medical_record_form_page.dart';
import 'presentation/patient_profile_page.dart';
import 'presentation/patients_page.dart';

/// Plugin de la clínica: perfil de atención (RF-04), servicios (RF-05),
/// agenda (RF-06) y registros médicos (pacientes vinculados y consultas).
class ClinicaPlugin extends MascotiPlugin {
  const ClinicaPlugin();

  @override
  String get id => 'clinica';

  @override
  Set<UserRole> get roles => const {UserRole.clinica};

  /// El calendario de la agenda (table_calendar) formatea fechas en español.
  @override
  Future<void> initialize() => initializeDateFormatting('es');

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
        GoRoute(
          path: ClinicaRoutes.patients,
          builder: (context, state) => const PatientsPage(),
        ),
        // Perfil del paciente y consultas a pantalla completa, con su barra
        // de título y botón atrás.
        GoRoute(
          path: ClinicaRoutes.patientPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              PatientProfilePage(petId: state.pathParameters['petId']!),
        ),
        GoRoute(
          path: ClinicaRoutes.newRecordPattern,
          parentNavigatorKey: rootNavigatorKey,
          // ?appointmentId=… cuando viene de "Registrar consulta" (RF-14).
          builder: (context, state) => MedicalRecordFormPage(
            petId: state.pathParameters['petId']!,
            appointmentId: state.uri.queryParameters['appointmentId'],
          ),
        ),
        GoRoute(
          path: ClinicaRoutes.recordPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => MedicalRecordFormPage(
            petId: state.pathParameters['petId']!,
            recordId: state.pathParameters['recordId'],
          ),
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
          label: 'Pacientes',
          icon: Icons.pets_outlined,
          selectedIcon: Icons.pets,
          path: ClinicaRoutes.patients,
          order: 10,
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
