import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error al generar o descargar el carnet, con el mensaje para mostrar.
@immutable
class HealthCardFailure implements Exception {
  const HealthCardFailure(this.message);

  final String message;

  static const network = HealthCardFailure('No se pudo conectar. Verifica tu conexión');
  static const generic = HealthCardFailure('No pudimos generar el carnet. Intenta de nuevo.');
  static const notConfigured =
      HealthCardFailure('El carnet PDF no está disponible en esta versión de la app');

  @override
  String toString() => 'HealthCardFailure($message)';
}

/// Último carnet generado: `pets/{petId}/documentos/carnet` (lo escribe la
/// Edge Function generar-carnet).
@immutable
class HealthCardInfo {
  const HealthCardInfo({required this.path, required this.generadoAt, required this.vacunas});

  final String path;
  final DateTime generadoAt;
  final int vacunas;

  static HealthCardInfo? fromMap(Map<String, dynamic>? data) {
    final at = data?['generadoAt'];
    if (data == null || at is! Timestamp) return null;
    return HealthCardInfo(
      path: data['path'] as String? ?? '',
      generadoAt: at.toDate(),
      vacunas: (data['vacunas'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Carnet recién generado, con el enlace firmado de 15 minutos.
@immutable
class GeneratedHealthCard {
  const GeneratedHealthCard({
    required this.url,
    required this.path,
    required this.generadoEn,
    required this.vacunas,
  });

  final String url;
  final String path;
  final DateTime generadoEn;
  final int vacunas;

  factory GeneratedHealthCard.fromMap(Map<String, dynamic> data) => GeneratedHealthCard(
        url: data['url'] as String,
        path: data['path'] as String? ?? '',
        generadoEn: DateTime.tryParse(data['generadoEn'] as String? ?? '') ?? DateTime.now(),
        vacunas: (data['vacunas'] as num?)?.toInt() ?? 0,
      );
}

/// Carnet de vacunas en PDF (RF-18). El PDF lo genera la Edge Function
/// `generar-carnet` (solo el dueño) y queda en el bucket privado `documentos`.
class HealthCardRepository {
  HealthCardRepository({
    FirebaseFirestore? firestore,
    FunctionsClient? functions,
    http.Client? httpClient,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions,
        _http = httpClient;

  final FirebaseFirestore _firestore;
  final FunctionsClient? _functions;
  final http.Client? _http;

  /// El PDF se dibuja en el servidor: puede tardar más que una consulta.
  static const _timeout = Duration(seconds: 40);

  Stream<HealthCardInfo?> watchLatest(String petId) => _firestore
      .doc('pets/$petId/documentos/carnet')
      .snapshots()
      .map((s) => HealthCardInfo.fromMap(s.data()));

  Future<GeneratedHealthCard> generate(String petId) async {
    final functions = _functions;
    if (functions == null) throw HealthCardFailure.notConfigured;
    try {
      final response =
          await functions.invoke('generar-carnet', body: {'petId': petId}).timeout(_timeout);
      return GeneratedHealthCard.fromMap(Map<String, dynamic>.from(response.data as Map));
    } on TimeoutException {
      throw HealthCardFailure.network;
    } on SocketException {
      throw HealthCardFailure.network;
    } on http.ClientException {
      throw HealthCardFailure.network;
    } on FunctionException catch (e) {
      final error = e.details is Map ? (e.details as Map)['error'] : null;
      final message = error is Map ? error['message'] as String? : null;
      throw HealthCardFailure(message ?? HealthCardFailure.generic.message);
    }
  }

  /// Bytes del PDF para compartirlo (el enlace vence a los 15 minutos).
  Future<Uint8List> download(String url) async {
    final client = _http ?? http.Client();
    try {
      final response = await client.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) {
        throw const HealthCardFailure('El enlace del carnet venció. Genéralo de nuevo.');
      }
      return response.bodyBytes;
    } on TimeoutException {
      throw HealthCardFailure.network;
    } on SocketException {
      throw HealthCardFailure.network;
    } on http.ClientException {
      throw HealthCardFailure.network;
    } finally {
      if (_http == null) client.close();
    }
  }
}
