import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'animal_type.dart';
import 'opening_hours.dart';

/// `clinics.estado`: pasa de incompleto a activo al configurar el perfil de
/// atención (RF-04).
enum ClinicStatus {
  incompleto('incompleto'),
  activo('activo');

  const ClinicStatus(this.value);

  final String value;

  /// Un valor desconocido se trata como incompleto (no aparece en búsquedas).
  static ClinicStatus fromValue(Object? value) =>
      value == activo.value ? activo : incompleto;
}

/// Documento `clinics/{clinicId}` (RF-01, RF-04, RF-06, RF-09).
/// Lo crea la Edge Function `completar-registro`; la clínica dueña edita
/// solo los campos que permiten las reglas (ver docs/modelo-datos.md).
@immutable
class Clinic {
  const Clinic({
    required this.id,
    required this.ownerUid,
    required this.nombre,
    required this.telefono,
    required this.direccion,
    required this.lat,
    required this.lng,
    this.geohash,
    this.tiposAnimales = const [],
    this.atencionEmergencias = false,
    this.horarioBase,
    this.calificacion,
    this.estado = ClinicStatus.incompleto,
    this.createdAt,
  });

  factory Clinic.fromMap(String id, Map<String, dynamic> map) {
    final geo = map['geo'];
    return Clinic(
      id: id,
      ownerUid: map['ownerUid'] as String? ?? '',
      nombre: map['nombre'] as String? ?? '',
      telefono: map['telefono'] as String? ?? '',
      direccion: map['direccion'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
      geohash: geo is Map ? geo['geohash'] as String? : null,
      tiposAnimales: AnimalType.listFrom(map['tiposAnimales']),
      atencionEmergencias: map['atencionEmergencias'] == true,
      horarioBase: map['horarioBase'] is Map
          ? OpeningHours.fromMap(Map<String, dynamic>.from(map['horarioBase'] as Map))
          : null,
      calificacion: (map['calificacion'] as num?)?.toDouble(),
      estado: ClinicStatus.fromValue(map['estado']),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String ownerUid;
  final String nombre;
  final String telefono;
  final String direccion;
  final double lat;
  final double lng;

  /// `geo.geohash` (RF-09): lo calcula el servidor a partir de lat/lng.
  final String? geohash;

  final List<AnimalType> tiposAnimales;
  final bool atencionEmergencias;

  /// null hasta que la clínica configure su horario (RF-06).
  final OpeningHours? horarioBase;

  final double? calificacion;
  final ClinicStatus estado;
  final DateTime? createdAt;

  bool get isActive => estado == ClinicStatus.activo;

  /// Mapa completo del documento. `geo` se escribe con GeoPoint, como lo lee
  /// geoflutterfire_plus. Para actualizar el perfil usa [toProfileUpdate].
  Map<String, dynamic> toMap() => {
        'ownerUid': ownerUid,
        'nombre': nombre,
        'telefono': telefono,
        'direccion': direccion,
        'lat': lat,
        'lng': lng,
        'geo': {
          'geohash': geohash,
          'geopoint': GeoPoint(lat, lng),
        },
        'tiposAnimales': [for (final t in tiposAnimales) t.value],
        'atencionEmergencias': atencionEmergencias,
        'horarioBase': horarioBase?.toMap(),
        'calificacion': calificacion,
        'estado': estado.value,
        'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      };

  /// Solo los campos que la clínica puede editar desde la app (RF-04, RF-06).
  /// Las reglas rechazan cualquier otro campo.
  Map<String, dynamic> toProfileUpdate() => {
        'tiposAnimales': [for (final t in tiposAnimales) t.value],
        'atencionEmergencias': atencionEmergencias,
        if (horarioBase != null) 'horarioBase': horarioBase!.toMap(),
        'telefono': telefono,
        'direccion': direccion,
        'estado': estado.value,
      };

  Clinic copyWith({
    String? nombre,
    String? telefono,
    String? direccion,
    List<AnimalType>? tiposAnimales,
    bool? atencionEmergencias,
    OpeningHours? horarioBase,
    ClinicStatus? estado,
  }) =>
      Clinic(
        id: id,
        ownerUid: ownerUid,
        nombre: nombre ?? this.nombre,
        telefono: telefono ?? this.telefono,
        direccion: direccion ?? this.direccion,
        lat: lat,
        lng: lng,
        geohash: geohash,
        tiposAnimales: tiposAnimales ?? this.tiposAnimales,
        atencionEmergencias: atencionEmergencias ?? this.atencionEmergencias,
        horarioBase: horarioBase ?? this.horarioBase,
        calificacion: calificacion,
        estado: estado ?? this.estado,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Clinic &&
      other.id == id &&
      other.ownerUid == ownerUid &&
      other.nombre == nombre &&
      other.telefono == telefono &&
      other.direccion == direccion &&
      other.lat == lat &&
      other.lng == lng &&
      other.geohash == geohash &&
      listEquals(other.tiposAnimales, tiposAnimales) &&
      other.atencionEmergencias == atencionEmergencias &&
      other.horarioBase == horarioBase &&
      other.calificacion == calificacion &&
      other.estado == estado &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        ownerUid,
        nombre,
        telefono,
        direccion,
        lat,
        lng,
        geohash,
        Object.hashAll(tiposAnimales),
        atencionEmergencias,
        horarioBase,
        calificacion,
        estado,
        createdAt,
      );
}
