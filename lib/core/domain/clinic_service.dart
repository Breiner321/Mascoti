import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Categoría de un servicio (RF-05). [value] se guarda en Firestore.
enum ServiceCategory {
  vacunacion('vacunacion', 'Vacunación'),
  peluqueria('peluqueria', 'Peluquería'),
  bano('bano', 'Baño'),
  cirugia('cirugia', 'Cirugía'),
  consultaGeneral('consulta_general', 'Consulta general'),
  otro('otro', 'Otro');

  const ServiceCategory(this.value, this.label);

  final String value;
  final String label;

  /// Un valor desconocido se muestra como "Otro".
  static ServiceCategory fromValue(Object? value) {
    for (final c in values) {
      if (c.value == value) return c;
    }
    return otro;
  }
}

/// Documento `clinics/{clinicId}/services/{serviceId}` (RF-05).
/// No se borra: se desactiva con `activo: false` (soft delete).
@immutable
class ClinicService {
  const ClinicService({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.precio,
    required this.duracionMin,
    this.descripcion = '',
    this.activo = true,
    this.createdAt,
    this.updatedAt,
  });

  factory ClinicService.fromMap(String id, Map<String, dynamic> map) => ClinicService(
        id: id,
        nombre: map['nombre'] as String? ?? '',
        categoria: ServiceCategory.fromValue(map['categoria']),
        descripcion: map['descripcion'] as String? ?? '',
        precio: (map['precio'] as num?)?.toDouble() ?? 0,
        duracionMin: (map['duracionMin'] as num?)?.toInt() ?? 0,
        activo: map['activo'] != false,
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      );

  final String id;
  final String nombre;
  final ServiceCategory categoria;
  final String descripcion;

  /// En pesos colombianos; RF-05 permite hasta 2 decimales.
  final double precio;

  /// Entero entre 5 y 480 (RF-05).
  final int duracionMin;
  final bool activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'categoria': categoria.value,
        'descripcion': descripcion,
        'precio': precio,
        'duracionMin': duracionMin,
        'activo': activo,
        'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
        'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      };

  ClinicService copyWith({
    String? nombre,
    ServiceCategory? categoria,
    String? descripcion,
    double? precio,
    int? duracionMin,
    bool? activo,
    DateTime? updatedAt,
  }) =>
      ClinicService(
        id: id,
        nombre: nombre ?? this.nombre,
        categoria: categoria ?? this.categoria,
        descripcion: descripcion ?? this.descripcion,
        precio: precio ?? this.precio,
        duracionMin: duracionMin ?? this.duracionMin,
        activo: activo ?? this.activo,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is ClinicService &&
      other.id == id &&
      other.nombre == nombre &&
      other.categoria == categoria &&
      other.descripcion == descripcion &&
      other.precio == precio &&
      other.duracionMin == duracionMin &&
      other.activo == activo &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        nombre,
        categoria,
        descripcion,
        precio,
        duracionMin,
        activo,
        createdAt,
        updatedAt,
      );
}
