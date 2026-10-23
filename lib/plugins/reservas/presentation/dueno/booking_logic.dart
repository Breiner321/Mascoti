import '../../../../core/domain/appointment.dart';
import '../../../../core/domain/slot.dart';

/// Reglas del lado dueño de RF-14, sin widgets para poder probarlas.
abstract final class BookingLogic {
  /// Mensaje del botón "Cancelar cita" deshabilitado (igual al del servidor).
  static const cancelTooLate =
      'Solo puedes cancelar hasta 2 horas antes de la cita. Comunícate con la clínica.';

  /// Franjas que el dueño puede pedir para [serviceId]: disponibles, de ese
  /// servicio y que todavía no empiezan; por hora de inicio.
  static List<Slot> bookableSlots(
    Iterable<Slot> slots, {
    required String serviceId,
    required DateTime now,
  }) =>
      [
        for (final s in slots)
          if (s.estado == SlotStatus.disponible &&
              s.serviceId == serviceId &&
              s.inicio.isAfter(now))
            s,
      ]..sort((a, b) => a.inicio.compareTo(b.inicio));

  /// Días ('YYYY-MM-DD', hora de Bogotá) con al menos una franja que se
  /// puede pedir para [serviceId]: los que se resaltan en el calendario.
  static Set<String> availableDays(
    Iterable<Slot> slots, {
    required String serviceId,
    required DateTime now,
  }) =>
      {for (final s in bookableSlots(slots, serviceId: serviceId, now: now)) s.fecha};

  /// Horas que se pueden pedir el día [fecha], por hora.
  static List<Slot> hoursOf(
    Iterable<Slot> slots, {
    required String serviceId,
    required String fecha,
    required DateTime now,
  }) =>
      [
        for (final s in bookableSlots(slots, serviceId: serviceId, now: now))
          if (s.fecha == fecha) s,
      ];

  /// Una cita va en "Próximas" mientras esté pendiente o confirmada y no haya
  /// pasado la tolerancia de no-show (después la cierra la tarea programada).
  static bool isUpcoming(Appointment a, DateTime now) =>
      a.estado.isActive &&
      a.inicio.add(AppointmentLimits.noShowTolerance).isAfter(now);

  /// "Mis citas": Próximas (la más cercana primero) e Historial (la más
  /// reciente primero).
  static ({List<Appointment> upcoming, List<Appointment> history}) split(
    Iterable<Appointment> appointments,
    DateTime now,
  ) {
    final upcoming = <Appointment>[];
    final history = <Appointment>[];
    for (final a in appointments) {
      (isUpcoming(a, now) ? upcoming : history).add(a);
    }
    upcoming.sort((a, b) => a.inicio.compareTo(b.inicio));
    history.sort((a, b) => b.inicio.compareTo(a.inicio));
    return (upcoming: upcoming, history: history);
  }

  /// Por qué el dueño no puede cancelar todavía una cita activa, o null si
  /// puede (o si la cita ya terminó y el botón ni se muestra).
  static String? cancelBlockedReason(Appointment a, DateTime now) {
    if (!canTransition(a.estado, AppointmentStatus.cancelada)) return null;
    return a.ownerCanCancel(now) ? null : cancelTooLate;
  }

  /// "Tus clínicas": clínicas de citas anteriores, sin repetir, de la más
  /// reciente a la más antigua.
  static List<({String id, String nombre})> recentClinics(
    Iterable<Appointment> appointments,
  ) {
    final sorted = [...appointments]..sort((a, b) => b.inicio.compareTo(a.inicio));
    final seen = <String>{};
    return [
      for (final a in sorted)
        if (a.clinicId.isNotEmpty && seen.add(a.clinicId))
          (id: a.clinicId, nombre: a.clinicNombre),
    ];
  }
}
