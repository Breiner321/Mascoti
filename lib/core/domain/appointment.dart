import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Estado de una cita (RF-14). [value] se guarda en Firestore.
///
/// Las transiciones válidas están en [canTransition], igual que en
/// `supabase/functions/_shared/estados_cita.ts`: si cambias una, cambia la
/// otra. Solo el servidor cambia el estado; la app lo usa para decidir qué
/// botones mostrar.
enum AppointmentStatus {
  pendiente('pendiente', 'Pendiente'),
  confirmada('confirmada', 'Confirmada'),
  rechazada('rechazada', 'Rechazada'),
  cancelada('cancelada', 'Cancelada'),
  expirada('expirada', 'Expirada'),
  completada('completada', 'Completada'),
  noAsistio('no_asistio', 'No asistió');

  const AppointmentStatus(this.value, this.label);

  final String value;
  final String label;

  /// null si el valor no es un estado conocido.
  static AppointmentStatus? fromValue(Object? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return null;
  }

  /// A qué estados puede pasar una cita en este estado.
  Set<AppointmentStatus> get nextStates => _transitions[this]!;

  /// Ya no cambia (rechazada, cancelada, expirada, completada, no asistió).
  bool get isFinal => nextStates.isEmpty;

  /// Pendiente o confirmada: todavía ocupa la franja.
  bool get isActive => !isFinal;
}

const _transitions = <AppointmentStatus, Set<AppointmentStatus>>{
  AppointmentStatus.pendiente: {
    AppointmentStatus.confirmada,
    AppointmentStatus.rechazada,
    AppointmentStatus.cancelada,
    AppointmentStatus.expirada,
  },
  AppointmentStatus.confirmada: {
    AppointmentStatus.completada,
    AppointmentStatus.cancelada,
    AppointmentStatus.noAsistio,
  },
  AppointmentStatus.rechazada: {},
  AppointmentStatus.cancelada: {},
  AppointmentStatus.expirada: {},
  AppointmentStatus.completada: {},
  AppointmentStatus.noAsistio: {},
};

/// Máquina de estados de la cita: true si puede pasar de [from] a [to].
///
/// ```
/// pendiente  → confirmada | rechazada | cancelada | expirada
/// confirmada → completada | cancelada | no_asistio
/// ```
bool canTransition(AppointmentStatus from, AppointmentStatus to) =>
    _transitions[from]!.contains(to);

/// Quién canceló la cita.
enum CancelledBy {
  dueno('dueno'),
  clinica('clinica');

  const CancelledBy(this.value);

  final String value;

  static CancelledBy? fromValue(Object? value) {
    for (final c in values) {
      if (c.value == value) return c;
    }
    return null;
  }
}

/// Límites y plazos de las citas (iguales a `_shared/citas.ts`).
abstract final class AppointmentLimits {
  static const maxComentario = 500;
  static const maxMotivo = 300;

  /// El dueño puede cancelar hasta 2 horas antes (RF-14).
  static const ownerCancelWindow = Duration(hours: 2);

  /// Sin marcarla como completada, pasa a "no asistió" 60 min después.
  static const noShowTolerance = Duration(minutes: 60);
}

/// Documento `appointments/{appointmentId}` (RF-14). Lo crea y lo cambia
/// solo la Edge Function `citas`; la app lo lee.
@immutable
class Appointment {
  const Appointment({
    required this.id,
    required this.clinicId,
    required this.clinicNombre,
    required this.ownerUid,
    required this.petId,
    required this.petNombre,
    required this.serviceId,
    required this.serviceNombre,
    required this.precioAcordado,
    required this.slotId,
    required this.fecha,
    required this.hora,
    required this.inicio,
    required this.estado,
    this.clinicOwnerUid = '',
    this.ownerNombre = '',
    this.duracionMin,
    this.slotIds = const [],
    this.comentario = '',
    this.motivoRechazo,
    this.motivoCancelacion,
    this.canceladoPor,
    this.createdAt,
    this.updatedAt,
  });

  factory Appointment.fromMap(String id, Map<String, dynamic> map) => Appointment(
        id: id,
        clinicId: map['clinicId'] as String? ?? '',
        clinicNombre: map['clinicNombre'] as String? ?? '',
        clinicOwnerUid: map['clinicOwnerUid'] as String? ?? '',
        ownerUid: map['ownerUid'] as String? ?? '',
        ownerNombre: map['ownerNombre'] as String? ?? '',
        petId: map['petId'] as String? ?? '',
        petNombre: map['petNombre'] as String? ?? '',
        serviceId: map['serviceId'] as String? ?? '',
        serviceNombre: map['serviceNombre'] as String? ?? '',
        precioAcordado: (map['precioAcordado'] as num?)?.toDouble() ?? 0,
        duracionMin: (map['duracionMin'] as num?)?.toInt(),
        slotId: map['slotId'] as String? ?? '',
        slotIds: map['slotIds'] is List
            ? [for (final v in map['slotIds'] as List) if (v is String) v]
            : const [],
        fecha: map['fecha'] as String? ?? '',
        hora: map['hora'] as String? ?? '',
        inicio: (map['inicio'] as Timestamp?)?.toDate().toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        comentario: map['comentario'] as String? ?? '',
        // Un estado desconocido (versión nueva del servidor) se muestra como
        // terminado para no ofrecer acciones que el servidor rechazaría.
        estado: AppointmentStatus.fromValue(map['estado']) ?? AppointmentStatus.expirada,
        motivoRechazo: map['motivoRechazo'] as String?,
        motivoCancelacion: map['motivoCancelacion'] as String?,
        canceladoPor: CancelledBy.fromValue(map['canceladoPor']),
        createdAt: (map['createdAt'] as Timestamp?)?.toDate().toUtc(),
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate().toUtc(),
      );

  final String id;
  final String clinicId;

  /// Copias para mostrar sin leer otros documentos (la clínica no puede leer
  /// `users`, el dueño no necesita leer el servicio).
  final String clinicNombre;
  final String clinicOwnerUid;
  final String ownerUid;
  final String ownerNombre;
  final String petId;
  final String petNombre;
  final String serviceId;
  final String serviceNombre;

  /// Precio del servicio al momento de pedir la cita (COP).
  final double precioAcordado;
  final int? duracionMin;

  /// `{fecha}_{hora}` de `clinics/{clinicId}/slots`: la primera franja.
  final String slotId;

  /// Todas las franjas que aparta la cita (Cambio 2: un servicio de 60 min
  /// con franjas de 30 aparta 2). Vacío en citas anteriores al cambio; usa
  /// [allSlotIds].
  final List<String> slotIds;

  /// Franjas de la cita, también para las anteriores al Cambio 2.
  List<String> get allSlotIds => slotIds.isNotEmpty ? slotIds : [if (slotId.isNotEmpty) slotId];

  /// 'YYYY-MM-DD' y 'HH:mm' (24 h) en hora de Bogotá.
  final String fecha;
  final String hora;

  /// Instante de inicio (en UTC), calculado en hora de Bogotá.
  final DateTime inicio;

  /// Comentario opcional del dueño (p. ej. "Vómito desde ayer").
  final String comentario;
  final AppointmentStatus estado;
  final String? motivoRechazo;
  final String? motivoCancelacion;
  final CancelledBy? canceladoPor;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// El dueño puede cancelar: pendiente o confirmada y faltan 2 h o más.
  bool ownerCanCancel(DateTime now) =>
      canTransition(estado, AppointmentStatus.cancelada) &&
      !now.isAfter(inicio.subtract(AppointmentLimits.ownerCancelWindow));

  /// La clínica puede marcarla como completada: confirmada y ya empezó.
  bool canComplete(DateTime now) =>
      canTransition(estado, AppointmentStatus.completada) && !now.isBefore(inicio);

  /// Cancelada por la clínica (el dueño recibe un aviso con prioridad alta).
  bool get cancelledByClinic =>
      estado == AppointmentStatus.cancelada && canceladoPor == CancelledBy.clinica;

  Map<String, dynamic> toMap() => {
        'clinicId': clinicId,
        'clinicNombre': clinicNombre,
        'clinicOwnerUid': clinicOwnerUid,
        'ownerUid': ownerUid,
        'ownerNombre': ownerNombre,
        'petId': petId,
        'petNombre': petNombre,
        'serviceId': serviceId,
        'serviceNombre': serviceNombre,
        'precioAcordado': precioAcordado,
        'duracionMin': duracionMin,
        'slotId': slotId,
        if (slotIds.isNotEmpty) 'slotIds': slotIds,
        'fecha': fecha,
        'hora': hora,
        'inicio': Timestamp.fromDate(inicio),
        'comentario': comentario,
        'estado': estado.value,
        if (motivoRechazo != null) 'motivoRechazo': motivoRechazo,
        if (motivoCancelacion != null) 'motivoCancelacion': motivoCancelacion,
        if (canceladoPor != null) 'canceladoPor': canceladoPor!.value,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  Appointment copyWith({
    AppointmentStatus? estado,
    String? motivoRechazo,
    String? motivoCancelacion,
    CancelledBy? canceladoPor,
  }) =>
      Appointment(
        id: id,
        clinicId: clinicId,
        clinicNombre: clinicNombre,
        clinicOwnerUid: clinicOwnerUid,
        ownerUid: ownerUid,
        ownerNombre: ownerNombre,
        petId: petId,
        petNombre: petNombre,
        serviceId: serviceId,
        serviceNombre: serviceNombre,
        precioAcordado: precioAcordado,
        duracionMin: duracionMin,
        slotId: slotId,
        slotIds: slotIds,
        fecha: fecha,
        hora: hora,
        inicio: inicio,
        comentario: comentario,
        estado: estado ?? this.estado,
        motivoRechazo: motivoRechazo ?? this.motivoRechazo,
        motivoCancelacion: motivoCancelacion ?? this.motivoCancelacion,
        canceladoPor: canceladoPor ?? this.canceladoPor,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Appointment &&
      other.id == id &&
      other.clinicId == clinicId &&
      other.clinicNombre == clinicNombre &&
      other.clinicOwnerUid == clinicOwnerUid &&
      other.ownerUid == ownerUid &&
      other.ownerNombre == ownerNombre &&
      other.petId == petId &&
      other.petNombre == petNombre &&
      other.serviceId == serviceId &&
      other.serviceNombre == serviceNombre &&
      other.precioAcordado == precioAcordado &&
      other.duracionMin == duracionMin &&
      other.slotId == slotId &&
      listEquals(other.slotIds, slotIds) &&
      other.fecha == fecha &&
      other.hora == hora &&
      other.inicio == inicio &&
      other.comentario == comentario &&
      other.estado == estado &&
      other.motivoRechazo == motivoRechazo &&
      other.motivoCancelacion == motivoCancelacion &&
      other.canceladoPor == canceladoPor &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id, clinicId, clinicNombre, clinicOwnerUid, ownerUid, ownerNombre, petId, petNombre,
        serviceId, serviceNombre, precioAcordado, duracionMin, slotId, Object.hashAll(slotIds),
        fecha, hora, inicio,
        comentario, estado, motivoRechazo, motivoCancelacion, canceladoPor, createdAt, updatedAt,
      ]);
}
