import 'package:flutter/foundation.dart';

import '../data/clinics_geo_repository.dart';
import 'vet_place.dart';

/// Una veterinaria en el mapa (Cambio 4): aliada (clínica de Mascoti, con
/// citas y servicios) o no aliada (de OpenStreetMap, solo informativa).
/// La reutiliza el SOS (RF-10) para mostrar también las no aliadas.
@immutable
sealed class MapVet {
  const MapVet({required this.distanceKm});

  /// Distancia desde el usuario (o el punto de búsqueda).
  final double distanceKm;

  String get nombre;
  double get lat;
  double get lng;
  String? get telefono;

  /// Clave única en el mapa y la lista.
  String get key;
}

/// Clínica registrada y activa en Mascoti.
final class AllyVet extends MapVet {
  const AllyVet(this.nearby, {required super.distanceKm});

  final NearbyClinic nearby;

  @override
  String get nombre => nearby.clinic.nombre;
  @override
  double get lat => nearby.clinic.lat;
  @override
  double get lng => nearby.clinic.lng;
  @override
  String? get telefono => nearby.clinic.telefono.isEmpty ? null : nearby.clinic.telefono;
  @override
  String get key => 'aliado:${nearby.clinic.id}';
}

/// Veterinaria de OpenStreetMap que aún no usa Mascoti.
final class OsmVet extends MapVet {
  const OsmVet(this.place, {required super.distanceKm});

  final VetPlace place;

  @override
  String get nombre => place.nombre;
  @override
  double get lat => place.lat;
  @override
  double get lng => place.lng;
  @override
  String? get telefono => place.telefono;
  @override
  String get key => 'osm:${place.osmId}';
}

/// Une aliados y no aliados sin duplicados (Cambio 4): una clínica aliada
/// que también está en OpenStreetMap sale UNA vez, como aliada.
///
/// Se consideran el mismo lugar si:
/// 1. la clínica tiene guardado ese `osmId` (script `vincular-osm`), o
/// 2. están a menos de [maxMeters] y sus nombres se parecen (≥ [minSimilarity]).
/// Dos veterinarias cercanas con nombres distintos NO se fusionan.
abstract final class VetMatching {
  static const maxMeters = 50.0;
  static const minSimilarity = 0.5;

  /// Palabras que no distinguen una veterinaria de otra.
  static const _stopWords = {
    'clinica', 'veterinaria', 'veterinario', 'veterinarias', 'vet', 'centro', 'hospital',
    'consultorio', 'medico', 'medica', 'animal', 'animales', 'mascotas', 'mascota', 'pet', 'pets',
    'de', 'del', 'la', 'el', 'los', 'las', 'y', 'e', 'sas', 's.a.s', 'ltda', 'sa',
  };

  static const _accents = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
  };

  /// Palabras significativas del nombre: minúsculas, sin tildes ni
  /// signos y sin palabras comunes ("Clínica Veterinaria Patitas" → {patitas}).
  static Set<String> nameTokens(String name) => _plain(name)
      .split(RegExp(r'[^a-z0-9]+'))
      // Letras sueltas ("S.A.S.") no distinguen.
      .where((w) => w.length > 1 && !_stopWords.contains(w))
      .toSet();

  /// Minúsculas y sin tildes.
  static String _plain(String name) {
    var text = name.toLowerCase();
    _accents.forEach((a, b) => text = text.replaceAll(a, b));
    return text;
  }

  /// Parecido entre dos nombres, de 0 a 1 (palabras en común / palabras
  /// del nombre más corto). Si a alguno solo le quedan palabras comunes,
  /// compara los nombres completos normalizados.
  static double similarity(String a, String b) {
    final ta = nameTokens(a);
    final tb = nameTokens(b);
    if (ta.isEmpty || tb.isEmpty) {
      String norm(String s) => _plain(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      return norm(a) == norm(b) ? 1 : 0;
    }
    final common = ta.intersection(tb).length;
    return common / (ta.length < tb.length ? ta.length : tb.length);
  }

  static bool isSamePlace(NearbyClinic ally, VetPlace place) {
    final osmId = ally.clinic.osmId;
    if (osmId != null && osmId.isNotEmpty) return osmId == place.osmId;
    final meters = distanceKm(ally.clinic.lat, ally.clinic.lng, place.lat, place.lng) * 1000;
    return meters < maxMeters && similarity(ally.clinic.nombre, place.nombre) >= minSimilarity;
  }

  /// Aliados y no aliados en una lista, de la más cercana a la más lejana a
  /// ([fromLat], [fromLng]). Con [onlyAllies] no incluye las de OSM.
  static List<MapVet> merge({
    required List<NearbyClinic> allies,
    required List<VetPlace> places,
    required double fromLat,
    required double fromLng,
    bool onlyAllies = false,
  }) {
    final result = <MapVet>[
      for (final a in allies)
        AllyVet(a, distanceKm: distanceKm(fromLat, fromLng, a.clinic.lat, a.clinic.lng)),
      if (!onlyAllies)
        for (final p in places)
          if (!allies.any((a) => isSamePlace(a, p)))
            OsmVet(p, distanceKm: distanceKm(fromLat, fromLng, p.lat, p.lng)),
    ];
    result.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return result;
  }
}
