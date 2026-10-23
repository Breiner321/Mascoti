import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/appointment.dart';
import '../supabase/supabase_providers.dart';
import 'appointments_repository.dart';

final appointmentsRepositoryProvider = Provider<AppointmentsRepository>((ref) {
  return AppointmentsRepository(functions: ref.watch(supabaseClientProvider)?.functions);
});

/// "Mis citas" del dueño [ownerUid], en tiempo real.
final ownerAppointmentsProvider =
    StreamProvider.autoDispose.family<List<Appointment>, String>(
  (ref, ownerUid) =>
      ref.watch(appointmentsRepositoryProvider).watchOwnerAppointments(ownerUid),
  retry: (_, __) => null,
);

/// Solicitudes pendientes de la clínica [clinicId], en tiempo real.
final pendingRequestsProvider =
    StreamProvider.autoDispose.family<List<Appointment>, String>(
  (ref, clinicId) => ref.watch(appointmentsRepositoryProvider).watchPendingRequests(clinicId),
  retry: (_, __) => null,
);

/// Agenda de un día: `(clinicId: 'c1', day: DateTime(2026, 11, 5))`.
final clinicDayAgendaProvider = StreamProvider.autoDispose
    .family<List<Appointment>, ({String clinicId, DateTime day})>(
  (ref, q) => ref.watch(appointmentsRepositoryProvider).watchDay(q.clinicId, q.day),
  retry: (_, __) => null,
);

/// Una cita (pantalla de detalle), o null si no existe.
final appointmentProvider = StreamProvider.autoDispose.family<Appointment?, String>(
  (ref, appointmentId) =>
      ref.watch(appointmentsRepositoryProvider).watchAppointment(appointmentId),
  retry: (_, __) => null,
);
