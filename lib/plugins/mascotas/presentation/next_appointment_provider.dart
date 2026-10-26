import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/appointments_providers.dart';
import '../../../core/domain/appointment.dart';

/// Próxima cita pendiente o confirmada que todavía no empieza, de
/// cualquiera de las mascotas (la más cercana), o null.
Appointment? nextAppointmentOf(Iterable<Appointment> appointments, DateTime now) {
  Appointment? next;
  for (final a in appointments) {
    if (!a.estado.isActive || !a.inicio.isAfter(now)) continue;
    if (next == null || a.inicio.isBefore(next.inicio)) next = a;
  }
  return next;
}

/// Tarjeta "Próxima cita" del home (RF-14). Lee las citas del core; sin
/// datos todavía (o con error) muestra "Sin citas · Agendar".
final nextAppointmentProvider = Provider.autoDispose<Appointment?>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return null;
  final list = ref.watch(ownerAppointmentsProvider(uid)).value;
  return list == null ? null : nextAppointmentOf(list, DateTime.now());
});
