import 'package:flutter/foundation.dart';

import '../../../core/domain/opening_hours.dart';
import '../../../core/domain/slot.dart';

/// Cambio en borrador sobre una franja (RF-06), antes de "Guardar
/// Disponibilidad".
@immutable
sealed class SlotEdit {
  const SlotEdit();
}

/// Marcar la franja "Disponible" para [serviceId] a [precio].
class MarkAvailable extends SlotEdit {
  const MarkAvailable({required this.serviceId, required this.precio});

  final String serviceId;
  final double precio;

  @override
  bool operator ==(Object other) =>
      other is MarkAvailable && other.serviceId == serviceId && other.precio == precio;

  @override
  int get hashCode => Object.hash(serviceId, precio);
}

/// Bloquear la franja (almuerzo, mantenimiento…), sin servicio.
class MarkUnavailable extends SlotEdit {
  const MarkUnavailable();

  @override
  bool operator ==(Object other) => other is MarkUnavailable;

  @override
  int get hashCode => 0;
}

/// Quitar la configuración: la franja deja de existir en Firestore.
class ClearSlot extends SlotEdit {
  const ClearSlot();

  @override
  bool operator ==(Object other) => other is ClearSlot;

  @override
  int get hashCode => 1;
}

/// Cómo se ve una franja en la vista del día.
enum FranjaKind {
  /// Sin documento: no se ofrece a los dueños.
  empty,

  /// 'disponible', con servicio y precio.
  available,

  /// 'no_disponible'.
  unavailable,

  /// 'ocupado' o 'reservado_temporal': solo lectura.
  locked,

  /// Sin documento propio, pero dentro del rango de un servicio más largo
  /// que empieza antes (ver [Franja.coveredBy]).
  covered,
}

/// Una franja del día ya combinada: horario base + Firestore + borradores.
@immutable
class Franja {
  const Franja({
    required this.hora,
    required this.kind,
    this.slot,
    this.coveredBy,
    this.edited = false,
    this.conflict = false,
  });

  /// 'HH:mm'.
  final String hora;
  final FranjaKind kind;

  /// La franja efectiva (guardada o en borrador); null si no hay documento.
  final Slot? slot;

  /// Hora de la franja cuyo servicio cubre a esta (solo en [FranjaKind.covered]).
  final String? coveredBy;

  /// Tiene un cambio sin guardar.
  final bool edited;

  /// Participa en un solapamiento o termina después del cierre.
  final bool conflict;

  int get minutes => OpeningHours.minutesOf(hora);
}

/// Resultado de combinar el día: las franjas en orden y las horas con
/// conflictos (si hay alguna, no se puede guardar).
@immutable
class DayPlan {
  const DayPlan({required this.franjas, required this.conflicts});

  final List<Franja> franjas;
  final Set<String> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Cambios que hay que escribir en Firestore para un día.
@immutable
class DayChanges {
  const DayChanges({required this.upserts, required this.deletes});

  /// Franjas a crear o reemplazar ('disponible' o 'no_disponible').
  final List<Slot> upserts;

  /// Horas 'HH:mm' cuyo documento se borra.
  final List<String> deletes;

  bool get isEmpty => upserts.isEmpty && deletes.isEmpty;
  int get length => upserts.length + deletes.length;
}

/// Lógica de la agenda del día (RF-06). Funciones puras: no dependen de
/// Flutter ni de Firestore, y se prueban en test/plugins/clinica/day_schedule_test.dart.
abstract final class DaySchedule {
  /// Horas del día: las del horario base más las de franjas guardadas que no
  /// encajan en él (p. ej. si la clínica cambió su horario), ordenadas.
  static List<String> times(OpeningHours hours, Iterable<String> savedHoras) {
    final all = {...hours.slotTimes(), ...savedHoras};
    return all.toList()
      ..sort((a, b) => OpeningHours.minutesOf(a).compareTo(OpeningHours.minutesOf(b)));
  }

  /// Aplica [edits] sobre [saved] (por hora). Las franjas bloqueadas
  /// ('ocupado', 'reservado_temporal') ignoran cualquier borrador.
  static Map<String, Slot> effective({
    required String fecha,
    required Map<String, Slot> saved,
    required Map<String, SlotEdit> edits,
  }) {
    final result = Map<String, Slot>.of(saved);
    for (final MapEntry(key: hora, value: edit) in edits.entries) {
      if (saved[hora]?.estado.isLocked ?? false) continue;
      switch (edit) {
        case MarkAvailable(:final serviceId, :final precio):
          result[hora] = Slot.at(
            fecha: fecha,
            hora: hora,
            estado: SlotStatus.disponible,
            serviceId: serviceId,
            precio: precio,
          );
        case MarkUnavailable():
          result[hora] = Slot.at(fecha: fecha, hora: hora, estado: SlotStatus.noDisponible);
        case ClearSlot():
          result.remove(hora);
      }
    }
    return result;
  }

  /// Minutos que ocupa una franja: la duración de su servicio o, si no se
  /// conoce (servicio desactivado, 'no_disponible'), el tamaño de la franja.
  static int durationOf(Slot slot, Map<String, int> serviceDurations, int slotMinutes) {
    final serviceId = slot.serviceId;
    if (slot.estado == SlotStatus.noDisponible || serviceId == null) return slotMinutes;
    return serviceDurations[serviceId] ?? slotMinutes;
  }

  /// Horas en conflicto. Una franja con servicio ocupa de su hora a su hora
  /// más la duración del servicio; hay conflicto si ese rango:
  /// - contiene el inicio de otra franja con documento (cualquier estado), o
  /// - termina después del cierre.
  /// Un conflicto entre dos franjas bloqueadas no cuenta: la clínica no
  /// puede corregirlo.
  static Set<String> conflicts({
    required Map<String, Slot> slots,
    required OpeningHours hours,
    required Map<String, int> serviceDurations,
  }) {
    final close = OpeningHours.minutesOf(hours.cierre);
    final ordered = slots.values.toList()
      ..sort((a, b) => OpeningHours.minutesOf(a.hora).compareTo(OpeningHours.minutesOf(b.hora)));
    final result = <String>{};

    for (final slot in ordered) {
      if (slot.estado == SlotStatus.noDisponible) continue; // no tiene duración propia
      final start = OpeningHours.minutesOf(slot.hora);
      final end = start + durationOf(slot, serviceDurations, hours.duracionSlotMin);

      if (end > close && !slot.estado.isLocked) result.add(slot.hora);

      for (final other in ordered) {
        final otherStart = OpeningHours.minutesOf(other.hora);
        if (otherStart <= start || otherStart >= end) continue;
        if (slot.estado.isLocked && other.estado.isLocked) continue;
        result
          ..add(slot.hora)
          ..add(other.hora);
      }
    }
    return result;
  }

  /// Combina horario base, franjas guardadas y borradores en la vista del día.
  static DayPlan build({
    required String fecha,
    required OpeningHours hours,
    required Map<String, Slot> saved,
    required Map<String, SlotEdit> edits,
    required Map<String, int> serviceDurations,
  }) {
    final slots = effective(fecha: fecha, saved: saved, edits: edits);
    final conflictSet = conflicts(slots: slots, hours: hours, serviceDurations: serviceDurations);

    // Rangos de las franjas con servicio, para marcar las cubiertas.
    final ranges = [
      for (final s in slots.values)
        if (s.estado != SlotStatus.noDisponible)
          (
            hora: s.hora,
            start: OpeningHours.minutesOf(s.hora),
            end: OpeningHours.minutesOf(s.hora) +
                durationOf(s, serviceDurations, hours.duracionSlotMin),
          ),
    ];

    final franjas = [
      for (final hora in times(hours, slots.keys))
        _franja(
          hora: hora,
          slot: slots[hora],
          edited: _isEdited(saved[hora], slots[hora]),
          conflict: conflictSet.contains(hora),
          coveredBy: slots[hora] != null
              ? null
              : ranges
                  .where((r) {
                    final m = OpeningHours.minutesOf(hora);
                    return r.start < m && m < r.end;
                  })
                  .map((r) => r.hora)
                  .firstOrNull,
        ),
    ];
    return DayPlan(franjas: franjas, conflicts: conflictSet);
  }

  static Franja _franja({
    required String hora,
    required Slot? slot,
    required bool edited,
    required bool conflict,
    required String? coveredBy,
  }) {
    final kind = switch (slot?.estado) {
      null => coveredBy != null ? FranjaKind.covered : FranjaKind.empty,
      SlotStatus.disponible => FranjaKind.available,
      SlotStatus.noDisponible => FranjaKind.unavailable,
      SlotStatus.ocupado || SlotStatus.reservadoTemporal => FranjaKind.locked,
    };
    return Franja(
      hora: hora,
      kind: kind,
      slot: slot,
      coveredBy: kind == FranjaKind.covered ? coveredBy : null,
      edited: edited,
      conflict: conflict,
    );
  }

  static bool _isEdited(Slot? saved, Slot? current) {
    if (saved == null || current == null) return saved != current;
    return saved.estado != current.estado ||
        saved.serviceId != current.serviceId ||
        saved.precio != current.precio;
  }

  /// Lo que hay que escribir: las franjas que cambiaron respecto a [saved].
  static DayChanges changes({
    required String fecha,
    required Map<String, Slot> saved,
    required Map<String, SlotEdit> edits,
  }) {
    final slots = effective(fecha: fecha, saved: saved, edits: edits);
    final upserts = <Slot>[];
    final deletes = <String>[];
    for (final hora in edits.keys) {
      final before = saved[hora];
      final after = slots[hora];
      if (!_isEdited(before, after)) continue;
      if (after == null) {
        deletes.add(hora);
      } else {
        upserts.add(after);
      }
    }
    int byHora(String a, String b) =>
        OpeningHours.minutesOf(a).compareTo(OpeningHours.minutesOf(b));
    upserts.sort((a, b) => byHora(a.hora, b.hora));
    deletes.sort(byHora);
    return DayChanges(upserts: upserts, deletes: deletes);
  }

  /// La franja ya empezó (o el día ya pasó): se ve, pero no se edita.
  static bool isPast(String fecha, String hora, DateTime now) =>
      !DateTime.parse('${fecha}T$hora:00').isAfter(now);
}
