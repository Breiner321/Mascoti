import '../../../../core/domain/appointment.dart';
import '../../../../core/domain/availability.dart';
import '../../../../core/domain/clinic.dart';
import '../../../../core/domain/schedule_exception.dart';
import '../../../../core/domain/slot.dart';

/// Reglas del lado dueño de RF-14, sin widgets para poder probarlas.
abstract final class BookingLogic {
  /// Mensaje del botón "Cancelar cita" deshabilitado (igual al del servidor).
  static const cancelTooLate =
      'Solo puedes cancelar hasta 2 horas antes de la cita. Comunícate con la clínica.';

  /// Horas ('HH:mm') en las que se puede pedir un servicio de [durationMin]
  /// el día [fecha] (Cambio 2): las calcula la función del core
  /// [Availability.startTimes] con el horario de la clínica, sus excepciones
  /// y las franjas ya apartadas ([slots]). La misma lógica valida el servidor.
  static List<String> hoursOf({
    required Clinic clinic,
    required int durationMin,
    required String fecha,
    required Iterable<Slot> slots,
    required DateTime now,
    Iterable<ScheduleException> exceptions = const [],
  }) {
    final schedule = clinic.schedule;
    if (schedule == null) return const [];
    return Availability.startTimes(
      fecha: fecha,
      durationMin: durationMin,
      schedule: schedule,
      settings: clinic.bookingSettings,
      now: now,
      exceptions: exceptions,
      slotStates: {
        for (final s in slots)
          if (s.fecha == fecha) s.hora: s.estado.value,
      },
    );
  }

  /// Días ('YYYY-MM-DD', hora de Bogotá) del mes [year]-[month] con al menos
  /// una hora libre: los que se resaltan en el calendario.
  static Set<String> availableDays({
    required Clinic clinic,
    required int durationMin,
    required int year,
    required int month,
    required Iterable<Slot> slots,
    required DateTime now,
    Iterable<ScheduleException> exceptions = const [],
  }) {
    final days = DateTime.utc(year, month + 1, 0).day;
    return {
      for (var d = 1; d <= days; d++)
        if (hoursOf(
          clinic: clinic,
          durationMin: durationMin,
          fecha: Slot.dateKey(DateTime(year, month, d)),
          slots: slots,
          now: now,
          exceptions: exceptions,
        ).isNotEmpty)
          Slot.dateKey(DateTime(year, month, d)),
    };
  }

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
