import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Veterinaria de OpenStreetMap que aún no usa Mascoti (Cambio 4): solo
/// informativa (sin citas ni servicios). La entrega la Edge Function
/// `veterinarias-cercanas`; igual a `VeterinariaOsm` en TS.
@immutable
class VetPlace {
  const VetPlace({
    required this.osmId,
    required this.nombre,
    required this.lat,
    required this.lng,
    this.direccion,
    this.telefono,
    this.horario,
    this.sitioWeb,
  });

  factory VetPlace.fromMap(Map<String, dynamic> map) => VetPlace(
        osmId: map['osmId'] as String? ?? '',
        nombre: map['nombre'] as String? ?? 'Veterinaria',
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
        direccion: map['direccion'] as String?,
        telefono: map['telefono'] as String?,
        horario: map['horario'] as String?,
        sitioWeb: map['sitioWeb'] as String?,
      );

  /// 'node/123', 'way/456': identifica el lugar en OSM.
  final String osmId;
  final String nombre;
  final double lat;
  final double lng;
  final String? direccion;
  final String? telefono;

  /// `opening_hours` de OSM tal cual ("Mo-Fr 08:00-18:00"); para mostrarlo
  /// usa `OsmHours.toSpanish`.
  final String? horario;
  final String? sitioWeb;

  @override
  bool operator ==(Object other) =>
      other is VetPlace &&
      other.osmId == osmId &&
      other.nombre == nombre &&
      other.lat == lat &&
      other.lng == lng &&
      other.direccion == direccion &&
      other.telefono == telefono &&
      other.horario == horario &&
      other.sitioWeb == sitioWeb;

  @override
  int get hashCode =>
      Object.hash(osmId, nombre, lat, lng, direccion, telefono, horario, sitioWeb);
}

/// Área rectangular del mapa (lo que se ve), en grados.
@immutable
class MapArea {
  const MapArea({required this.sur, required this.oeste, required this.norte, required this.este});

  /// Área de [radiusKm] alrededor de un punto (antes de que el mapa reporte
  /// lo que de verdad se ve).
  factory MapArea.around(double lat, double lng, double radiusKm) {
    final dLat = radiusKm / _kmPerDegree;
    final dLng = radiusKm / (_kmPerDegree * math.cos(lat * math.pi / 180));
    return MapArea(sur: lat - dLat, oeste: lng - dLng, norte: lat + dLat, este: lng + dLng);
  }

  static const _kmPerDegree = 111.32;

  /// Lado máximo que consulta el servidor (igual a MAX_LADO_KM en TS).
  static const maxSideKm = 30.0;

  final double sur;
  final double oeste;
  final double norte;
  final double este;

  double get centerLat => (sur + norte) / 2;
  double get centerLng => (oeste + este) / 2;

  double get heightKm => (norte - sur) * _kmPerDegree;
  double get widthKm => (este - oeste) * _kmPerDegree * math.cos(centerLat * math.pi / 180);

  /// Distancia del centro a una esquina: el radio que cubre todo lo visible.
  double get halfDiagonalKm => math.sqrt(heightKm * heightKm + widthKm * widthKm) / 2;

  /// Muy grande para pedir las veterinarias de OSM ("Acerca el mapa").
  bool get tooLargeForOsm => heightKm > maxSideKm || widthKm > maxSideKm;

  bool contains(double lat, double lng) =>
      lat >= sur && lat <= norte && lng >= oeste && lng <= este;

  /// Redondeada a ~100 m: mover el mapa unos metros no repite la consulta.
  MapArea rounded() {
    double r(double v) => (v * 1000).roundToDouble() / 1000;
    return MapArea(sur: r(sur), oeste: r(oeste), norte: r(norte), este: r(este));
  }

  Map<String, dynamic> toMap() => {'sur': sur, 'oeste': oeste, 'norte': norte, 'este': este};

  @override
  bool operator ==(Object other) =>
      other is MapArea &&
      other.sur == sur &&
      other.oeste == oeste &&
      other.norte == norte &&
      other.este == este;

  @override
  int get hashCode => Object.hash(sur, oeste, norte, este);

  @override
  String toString() => 'MapArea($sur, $oeste, $norte, $este)';
}

/// Distancia en km entre dos puntos (haversine).
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
