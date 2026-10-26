import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import '../../core/router/navigator_keys.dart';
import 'presentation/appointments_page.dart';
import 'presentation/clinica/clinic_appointment_detail_page.dart';
import 'presentation/clinica/clinic_requests_providers.dart';
import 'presentation/dueno/appointment_detail_page.dart';
import 'presentation/dueno/booking_page.dart';
import 'presentation/dueno/owner_routes.dart';

/// Plugin compartido por ambos roles: agendamiento y aprobación de citas (RF-14).
/// Ejemplo de plugin que aporta pestañas distintas según el rol.
class ReservasPlugin extends MascotiPlugin {
  const ReservasPlugin();

  @override
  String get id => 'reservas';

  @override
  Set<UserRole> get roles => const {UserRole.dueno, UserRole.clinica};

  /// Nombres de meses y días del calendario de "Agendar cita".
  @override
  Future<void> initialize() => initializeDateFormatting('es');

  @override
  List<RouteBase> routes() => [
        GoRoute(
          path: '/reservas',
          builder: (context, state) => const AppointmentsPage(),
        ),
        // Dueño (RF-14). `nueva` va antes de `:id` para que no la tome como id.
        GoRoute(
          path: OwnerBookingRoutes.newAppointment,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => BookingPage(
            clinicId: state.uri.queryParameters['clinicId'],
            categoria: state.uri.queryParameters['categoria'],
          ),
        ),
        GoRoute(
          path: OwnerBookingRoutes.detailPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => Consumer(
            builder: (context, ref, _) => ref.watch(currentUserProvider)?.role == UserRole.clinica
                ? ClinicAppointmentDetailPage(appointmentId: state.pathParameters['id']!)
                : AppointmentDetailPage(appointmentId: state.pathParameters['id']!),
          ),
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
        UserRole.clinica => [
            PluginDestination(
              label: 'Solicitudes',
              icon: Icons.inbox_outlined,
              selectedIcon: Icons.inbox,
              path: '/reservas',
              order: 10,
              // RF-14: número de solicitudes pendientes en la pestaña.
              badge: pendingRequestsCountProvider,
            ),
          ],
      };
}
