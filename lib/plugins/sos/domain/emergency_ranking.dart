import 'package:flutter/foundation.dart';

import '../../../core/data/saved_clinics_store.dart';
import '../../../core/domain/map_vet.dart';
import '../../../core/domain/vet_place.dart';

/// Veterinaria en la lista del SOS, con su distancia si se conoce la
/// ubicación (sin ubicación, las guardadas no tienen distancia).
@immutable
class EmergencyVet {
  const EmergencyVet(this.clinic, {this.distanceKm, this.favorite = false});

  final SavedClinic clinic;
  final double? distanceKm;

  /// Clínica de una cita anterior del dueño.
  final bool favorite;

  String get key => clinic.key;
  String get nombre => clinic.nombre;
  String? get telefono => clinic.telefono;

  /// 0: aliada con atención de emergencias · 1: de OpenStreetMap abierta
  /// 24 horas · 2: las demás.
  int get priority => clinic.aliada && clinic.emergencias
      ? 0
      : !clinic.aliada && clinic.abierto24h
          ? 1
          : 2;

  @override
  bool operator ==(Object other) =>
      other is EmergencyVet &&
      other.clinic == clinic &&
      other.distanceKm == distanceKm &&
      other.favorite == favorite;

  @override
  int get hashCode => Object.hash(clinic, distanceKm, favorite);
}

/// Orden y búsqueda del SOS (RF-10).
abstract final class EmergencyRanking {
  /// Radios de búsqueda de aliadas: se amplía de 10 en 10 km hasta tener
  /// [minResults] o llegar a 50 km (RF-10, flujo alternativo).
  static const radiiKm = [10.0, 20.0, 30.0, 40.0, 50.0];
  static const minResults = 3;

  /// Las veterinarias de OpenStreetMap se buscan en un cuadro de 20 km de
  /// lado (el servidor acepta hasta 30).
  static const osmRadiusKm = 10.0;

  /// Suficientes tarjetas para alguien con prisa.
  static const maxResults = 15;

  /// Primero las aliadas con emergencias, luego las de OpenStreetMap abiertas
  /// 24 horas, luego las demás; dentro de cada grupo, la más cercana primero
  /// (sin distancia: las favoritas y luego por nombre).
  static List<EmergencyVet> rank(Iterable<EmergencyVet> vets) {
    final list = [...vets]..sort((a, b) {
        final byPriority = a.priority.compareTo(b.priority);
        if (byPriority != 0) return byPriority;
        final da = a.distanceKm;
        final db = b.distanceKm;
        if (da != null && db != null && da != db) return da.compareTo(db);
        if (da != null && db == null) return -1;
        if (da == null && db != null) return 1;
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    return list.take(maxResults).toList();
  }

  /// Lista con la búsqueda en vivo: aliadas y OpenStreetMap sin duplicados.
  static List<EmergencyVet> live({
    required List<MapVet> merged,
    Set<String> favoriteKeys = const {},
  }) =>
      rank([
        for (final v in merged)
          EmergencyVet(
            SavedClinic.fromMapVet(v),
            distanceKm: v.distanceKm,
            favorite: favoriteKeys.contains(v.key),
          ),
      ]);

  /// Lista con lo guardado en el teléfono (sin conexión o sin ubicación):
  /// favoritas y últimas mostradas, sin repetir. Con [lat]/[lng] calcula la
  /// distancia a cada una.
  static List<EmergencyVet> saved(SavedClinics saved, {double? lat, double? lng}) {
    final favoriteKeys = {for (final c in saved.favorites) c.key};
    final seen = <String>{};
    return rank([
      for (final c in [...saved.favorites, ...saved.recent])
        if (seen.add(c.key))
          EmergencyVet(
            c,
            distanceKm: lat == null || lng == null ? null : distanceKm(lat, lng, c.lat, c.lng),
            favorite: favoriteKeys.contains(c.key),
          ),
    ]);
  }

  /// Siguiente radio si con [found] resultados en [radiusKm] aún faltan;
  /// null si ya basta o se llegó al máximo.
  static double? nextRadius(double radiusKm, int found) {
    if (found >= minResults) return null;
    for (final r in radiiKm) {
      if (r > radiusKm) return r;
    }
    return null;
  }
}

/// "850 m" o "2,3 km".
String distanceText(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  final text = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return '${text.replaceAll('.', ',')} km';
}
