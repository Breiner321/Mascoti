import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../format/bogota_time.dart';

/// Estado de una franja (RF-06, RF-14). [value] se guarda en Firestore.
enum SlotStatus {
  disponible('disponible', 'Disponible'),
  noDisponible('no_disponible', 'No disponible'),
  reservadoTemporal('reservado_temporal', 'Reservado'),
  ocupado('ocupado', 'Ocupado');

  const SlotStatus(this.value, this.label);

  final String value;
  final String label;

  /// Un valor desconocido se trata como no disponible (nunca se ofrece).
  static SlotStatus fromValue(Object? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return noDisponible;
  }

  /// La clínica no puede editar una franja con cita (RF-06, flujo alterno).
  bool get isLocked => this == ocupado || this == reservadoTemporal;
}

/// Documento `clinics/{clinicId}/slots/{fecha}_{hora}` (RF-06). El id es
/// determinístico para que no haya dos franjas a la misma hora.
@immutable
class Slot {
  const Slot({
    required this.fecha,
    required this.hora,
    required this.inicio,
    required this.estado,
    this.serviceId,
    this.precio,
  });

  /// Construye la franja calculando [inicio] en hora de Bogotá a partir de
  /// [fecha] 'YYYY-MM-DD' y [hora] 'HH:mm' (no depende de la zona horaria del
  /// teléfono). Lanza [FormatException] si el formato no sirve.
  factory Slot.at({
    required String fecha,
    required String hora,
    required SlotStatus estado,
    String? serviceId,
    double? precio,
  }) =>
      Slot(
        fecha: fecha,
        hora: hora,
        inicio: BogotaTime.tryParse(fecha, hora) ??
            (throw FormatException('Fecha u hora inválida', '$fecha $hora')),
        estado: estado,
        serviceId: serviceId,
        precio: precio,
      );

  factory Slot.fromMap(Map<String, dynamic> map) {
    final fecha = map['fecha'] as String? ?? '';
    final hora = map['hora'] as String? ?? '';
    return Slot(
      fecha: fecha,
      hora: hora,
      inicio: (map['inicio'] as Timestamp?)?.toDate().toUtc() ??
          BogotaTime.tryParse(fecha, hora) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      estado: SlotStatus.fromValue(map['estado']),
      serviceId: map['serviceId'] as String?,
      precio: (map['precio'] as num?)?.toDouble(),
    );
  }

  /// 'YYYY-MM-DD'.
  final String fecha;

  /// 'HH:mm' (24 h).
  final String hora;

  /// Instante de inicio (en UTC), calculado en hora de Bogotá.
  final DateTime inicio;
  final SlotStatus estado;

  /// Servicio permitido en la franja; null en franjas "No disponible".
  final String? serviceId;

  /// Precio del servicio al publicar la franja.
  final double? precio;

  /// Id del documento: '2026-10-15_09:30'.
  String get id => idFor(fecha, hora);

  static String idFor(String fecha, String hora) => '${fecha}_$hora';

  /// '2026-10-15' a partir de un DateTime (para consultar las franjas del día).
  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'fecha': fecha,
        'hora': hora,
        'inicio': Timestamp.fromDate(inicio),
        'estado': estado.value,
        'serviceId': serviceId,
        'precio': precio,
      };

  Slot copyWith({SlotStatus? estado, String? serviceId, double? precio}) => Slot(
        fecha: fecha,
        hora: hora,
        inicio: inicio,
        estado: estado ?? this.estado,
        serviceId: serviceId ?? this.serviceId,
        precio: precio ?? this.precio,
      );

  @override
  bool operator ==(Object other) =>
      other is Slot &&
      other.fecha == fecha &&
      other.hora == hora &&
      other.inicio == inicio &&
      other.estado == estado &&
      other.serviceId == serviceId &&
      other.precio == precio;

  @override
  int get hashCode => Object.hash(fecha, hora, inicio, estado, serviceId, precio);
}
