import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Tipo de notificación (RF-13). [value] se guarda en Firestore y viaja en el
/// push como `data.tipo`; igual a `TipoNotificacion` en
/// `supabase/functions/_shared/notificaciones.ts`.
enum NotificationType {
  citaNueva('cita_nueva'),
  citaAprobada('cita_aprobada'),
  citaRechazada('cita_rechazada'),
  citaCancelada('cita_cancelada'),
  recordatorioCita('recordatorio_cita'),
  vacuna('vacuna'),
  pedido('pedido'),
  mensaje('mensaje');

  const NotificationType(this.value);

  final String value;

  static NotificationType? fromValue(Object? value) {
    for (final t in values) {
      if (t.value == value) return t;
    }
    return null;
  }

  /// `referenciaId` es el id de una cita.
  bool get isAppointment => switch (this) {
        citaNueva || citaAprobada || citaRechazada || citaCancelada || recordatorioCita => true,
        _ => false,
      };
}

/// Documento `notifications/{id}`: lo crea el servidor; el usuario solo lo
/// marca como leído.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.uid,
    required this.tipo,
    required this.titulo,
    required this.cuerpo,
    required this.referenciaId,
    required this.leido,
    this.createdAt,
  });

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) => AppNotification(
        id: id,
        uid: map['uid'] as String? ?? '',
        tipo: NotificationType.fromValue(map['tipo']),
        titulo: map['titulo'] as String? ?? '',
        cuerpo: map['cuerpo'] as String? ?? '',
        referenciaId: map['referenciaId'] as String? ?? '',
        leido: map['leido'] as bool? ?? false,
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );

  final String id;
  final String uid;

  /// null si es un tipo que esta versión de la app no conoce.
  final NotificationType? tipo;
  final String titulo;
  final String cuerpo;

  /// Cita (`appointmentId`) o, para vacunas, la mascota (`petId`).
  final String referenciaId;
  final bool leido;

  /// null mientras el servidor no confirma la hora.
  final DateTime? createdAt;

  @override
  bool operator ==(Object other) =>
      other is AppNotification &&
      other.id == id &&
      other.uid == uid &&
      other.tipo == tipo &&
      other.titulo == titulo &&
      other.cuerpo == cuerpo &&
      other.referenciaId == referenciaId &&
      other.leido == leido &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, uid, tipo, titulo, cuerpo, referenciaId, leido, createdAt);
}
