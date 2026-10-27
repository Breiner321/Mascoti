import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/vet_place.dart';

/// No se pudieron cargar las veterinarias de OpenStreetMap.
@immutable
class VetPlacesFailure implements Exception {
  const VetPlacesFailure(this.message, {this.tooLarge = false});

  final String message;

  /// El área es muy grande: hay que acercar el mapa (no es un error).
  final bool tooLarge;

  static const tooLargeArea =
      VetPlacesFailure('Acerca el mapa para ver otras veterinarias.', tooLarge: true);
  static const unavailable = VetPlacesFailure('No se pudieron cargar otras veterinarias.');
  static const notConfigured =
      VetPlacesFailure('Las otras veterinarias no están disponibles en esta versión de la app');

  @override
  String toString() => 'VetPlacesFailure($message)';
}

/// Veterinarias de OpenStreetMap del área visible (Cambio 4), por la Edge
/// Function `veterinarias-cercanas` (que consulta Overpass con caché y
/// límite por usuario). La reutiliza el SOS (RF-10).
class VetPlacesRepository {
  VetPlacesRepository({FunctionsClient? functions}) : _functions = functions;

  /// null = Supabase no está configurado (falta env/dev.json).
  final FunctionsClient? _functions;

  static const functionName = 'veterinarias-cercanas';
  static const _timeout = Duration(seconds: 35);

  /// Lanza [VetPlacesFailure].
  Future<List<VetPlace>> fetchIn(MapArea area) async {
    if (area.tooLargeForOsm) throw VetPlacesFailure.tooLargeArea;
    final functions = _functions;
    if (functions == null) throw VetPlacesFailure.notConfigured;
    try {
      final response = await functions.invoke(functionName, body: area.toMap()).timeout(_timeout);
      final data = Map<String, dynamic>.from(response.data as Map);
      return [
        for (final v in data['veterinarias'] as List? ?? const [])
          VetPlace.fromMap(Map<String, dynamic>.from(v as Map)),
      ];
    } on TimeoutException {
      throw VetPlacesFailure.unavailable;
    } on SocketException {
      throw VetPlacesFailure.unavailable;
    } on http.ClientException {
      throw VetPlacesFailure.unavailable;
    } on FunctionException catch (e) {
      final error = e.details is Map ? (e.details as Map)['error'] : null;
      final code = error is Map ? error['code'] as String? : null;
      final message = error is Map ? error['message'] as String? : null;
      if (code == 'failed-precondition') throw VetPlacesFailure.tooLargeArea;
      throw VetPlacesFailure(message ?? VetPlacesFailure.unavailable.message);
    }
  }
}
