import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/clinic.dart';
import '../domain/map_vet.dart';

/// Veterinaria guardada en el teléfono para el SOS sin conexión ni
/// ubicación (RF-10): lo justo para llamar y llegar.
@immutable
class SavedClinic {
  const SavedClinic({
    required this.key,
    required this.nombre,
    required this.lat,
    required this.lng,
    this.telefono,
    this.aliada = false,
    this.emergencias = false,
    this.abierto24h = false,
  });

  factory SavedClinic.fromClinic(Clinic clinic) => SavedClinic(
        key: 'aliado:${clinic.id}',
        nombre: clinic.nombre,
        lat: clinic.lat,
        lng: clinic.lng,
        telefono: clinic.telefono.trim().isEmpty ? null : clinic.telefono.trim(),
        aliada: true,
        emergencias: clinic.atencionEmergencias,
      );

  factory SavedClinic.fromMapVet(MapVet vet) => switch (vet) {
        AllyVet(:final nearby) => SavedClinic.fromClinic(nearby.clinic),
        OsmVet(:final place) => SavedClinic(
            key: vet.key,
            nombre: place.nombre,
            lat: place.lat,
            lng: place.lng,
            telefono: place.telefono,
            abierto24h: place.horario?.trim() == '24/7',
          ),
      };

  factory SavedClinic.fromMap(Map<String, dynamic> map) => SavedClinic(
        key: map['key'] as String? ?? '',
        nombre: map['nombre'] as String? ?? 'Veterinaria',
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
        telefono: map['telefono'] as String?,
        aliada: map['aliada'] == true,
        emergencias: map['emergencias'] == true,
        abierto24h: map['abierto24h'] == true,
      );

  /// Igual a [MapVet.key]: `aliado:{clinicId}` u `osm:{osmId}`.
  final String key;
  final String nombre;
  final double lat;
  final double lng;
  final String? telefono;

  /// Clínica registrada en Mascoti ("Aliado Mascoti").
  final bool aliada;

  /// Aliada con `atencionEmergencias == true`.
  final bool emergencias;

  /// Veterinaria de OpenStreetMap con horario "24/7".
  final bool abierto24h;

  Map<String, dynamic> toMap() => {
        'key': key,
        'nombre': nombre,
        'lat': lat,
        'lng': lng,
        if (telefono != null) 'telefono': telefono,
        'aliada': aliada,
        'emergencias': emergencias,
        'abierto24h': abierto24h,
      };

  @override
  bool operator ==(Object other) =>
      other is SavedClinic &&
      other.key == key &&
      other.nombre == nombre &&
      other.lat == lat &&
      other.lng == lng &&
      other.telefono == telefono &&
      other.aliada == aliada &&
      other.emergencias == emergencias &&
      other.abierto24h == abierto24h;

  @override
  int get hashCode =>
      Object.hash(key, nombre, lat, lng, telefono, aliada, emergencias, abierto24h);
}

/// Lo guardado en el teléfono: las favoritas (clínicas de citas anteriores)
/// y las últimas veterinarias mostradas en el mapa o en el SOS.
typedef SavedClinics = ({List<SavedClinic> favorites, List<SavedClinic> recent});

/// Guarda veterinarias en `shared_preferences` para que el SOS (RF-10)
/// muestre algo al instante y sin conexión. Lo escriben el directorio
/// (lo que muestra el mapa) y el SOS; nunca lanza errores.
class SavedClinicsStore {
  static const favoritesKey = 'sos.favoritas';
  static const recentKey = 'sos.recientes';
  static const maxRecent = 10;
  static const maxFavorites = 10;

  /// Claves de la última lista guardada: no se reescribe la misma.
  String? _lastRecentKeys;

  Future<SavedClinics> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (favorites: _read(prefs, favoritesKey), recent: _read(prefs, recentKey));
    } catch (_) {
      return (favorites: const <SavedClinic>[], recent: const <SavedClinic>[]);
    }
  }

  Future<void> saveFavorites(List<SavedClinic> clinics) =>
      _write(favoritesKey, clinics.take(maxFavorites).toList());

  /// Las primeras [maxRecent] de [clinics] (ya ordenadas por distancia).
  Future<void> rememberShown(List<SavedClinic> clinics) async {
    if (clinics.isEmpty) return;
    final list = clinics.take(maxRecent).toList();
    final keys = list.map((c) => c.key).join('|');
    if (keys == _lastRecentKeys) return;
    _lastRecentKeys = keys;
    await _write(recentKey, list);
  }

  static List<SavedClinic> _read(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          if (item is Map) SavedClinic.fromMap(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _write(String key, List<SavedClinic> clinics) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode([for (final c in clinics) c.toMap()]));
    } catch (_) {
      // Guardar es una ayuda para el modo sin conexión: si falla, no pasa nada.
    }
  }
}

final savedClinicsStoreProvider = Provider<SavedClinicsStore>((ref) => SavedClinicsStore());
