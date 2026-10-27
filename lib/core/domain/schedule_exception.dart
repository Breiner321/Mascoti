import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'opening_hours.dart';

/// Tipo de excepción al horario semanal (Cambio 2).
enum ExceptionType {
  /// La clínica no atiende (franja, rango de horas o días completos).
  bloqueo('bloqueo'),

  /// Horario extra fuera del horario normal.
  apertura('apertura');

  const ExceptionType(this.value);

  final String value;

  static ExceptionType? fromValue(Object? value) {
    for (final t in values) {
      if (t.value == value) return t;
    }
    return null;
  }
}

/// `clinics/{clinicId}/excepciones/{id}` (Cambio 2). Cubre las fechas
/// [fechaInicio, fechaFin] (inclusive, 'YYYY-MM-DD' en hora de Bogotá) y,
/// dentro de cada una, [desde, hasta) — o el día completo si no tiene horas
/// (solo para bloqueos). Igual a `Excepcion` en
/// `supabase/functions/_shared/disponibilidad.ts`.
@immutable
class ScheduleException {
  const ScheduleException({
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFin,
    this.id = '',
    this.desde,
    this.hasta,
    this.motivo,
  });

  /// null si el documento no es válido (se ignora).
  static ScheduleException? tryFromMap(String id, Map<String, dynamic> map) {
    final tipo = ExceptionType.fromValue(map['tipo']);
    final inicio = map['fechaInicio'];
    final fin = map['fechaFin'];
    if (tipo == null || inicio is! String || fin is! String) return null;
    return ScheduleException(
      id: id,
      tipo: tipo,
      fechaInicio: inicio,
      fechaFin: fin,
      desde: map['desde'] as String?,
      hasta: map['hasta'] as String?,
      motivo: map['motivo'] as String?,
    );
  }

  static const maxMotivo = 120;

  final String id;
  final ExceptionType tipo;
  final String fechaInicio;
  final String fechaFin;
  final String? desde;
  final String? hasta;
  final String? motivo;

  bool get isFullDay => desde == null || hasta == null;

  /// ¿Aplica a la fecha 'YYYY-MM-DD'? (las fechas ISO se comparan como texto).
  bool covers(String fecha) =>
      fechaInicio.compareTo(fecha) <= 0 && fecha.compareTo(fechaFin) <= 0;

  /// Tramo del día en minutos: [inicio, fin). Día completo = [0, 1440).
  (int, int) get minutes => isFullDay
      ? (0, 24 * 60)
      : (OpeningHours.minutesOf(desde!), OpeningHours.minutesOf(hasta!));

  Map<String, dynamic> toMap() => {
        'tipo': tipo.value,
        'fechaInicio': fechaInicio,
        'fechaFin': fechaFin,
        if (!isFullDay) 'desde': desde,
        if (!isFullDay) 'hasta': hasta,
        if (motivo != null && motivo!.trim().isNotEmpty) 'motivo': motivo!.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      };

  @override
  bool operator ==(Object other) =>
      other is ScheduleException &&
      other.id == id &&
      other.tipo == tipo &&
      other.fechaInicio == fechaInicio &&
      other.fechaFin == fechaFin &&
      other.desde == desde &&
      other.hasta == hasta &&
      other.motivo == motivo;

  @override
  int get hashCode => Object.hash(id, tipo, fechaInicio, fechaFin, desde, hasta, motivo);
}
