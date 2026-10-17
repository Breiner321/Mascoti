import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mascota que la clínica acaba de vincular con su código de paciente.
@immutable
class LinkedPet {
  const LinkedPet({
    required this.petId,
    required this.codigoPaciente,
    required this.nombre,
    required this.especie,
    required this.duenoNombre,
    required this.nueva,
    this.fotoPath,
  });

  factory LinkedPet.fromMap(Map<String, dynamic> map) => LinkedPet(
        petId: map['petId'] as String? ?? '',
        codigoPaciente: map['codigoPaciente'] as String? ?? '',
        nombre: map['nombre'] as String? ?? '',
        especie: map['especie'] as String? ?? '',
        duenoNombre: map['duenoNombre'] as String? ?? '',
        fotoPath: map['fotoPath'] as String?,
        nueva: map['nueva'] != false,
      );

  final String petId;
  final String codigoPaciente;
  final String nombre;

  /// Valor de Firestore (`perro`, `gato`…): PetSpecies.fromValue.
  final String especie;
  final String duenoNombre;

  /// Ruta en el bucket `mascotas` (StorageRepository.signedUrl).
  final String? fotoPath;

  /// false si la clínica ya estaba autorizada.
  final bool nueva;
}

enum PetLinkFailureKind {
  /// No existe una mascota con ese código.
  notFound,

  /// El texto no tiene el formato MSC-XXXX.
  invalidCode,

  /// La clínica no está activa (falta el perfil de atención, RF-04).
  clinicInactive,

  /// No es una clínica o la cuenta está suspendida.
  notAllowed,

  /// Más de 10 intentos en una hora.
  tooManyAttempts,

  network,
  notConfigured,
  unknown,
}

/// Error de `vincular-mascota` con el mensaje para mostrar.
@immutable
class PetLinkFailure implements Exception {
  const PetLinkFailure(this.kind, {this.serverMessage});

  final PetLinkFailureKind kind;
  final String? serverMessage;

  /// El servidor ya envía el texto para el usuario; estos son de respaldo.
  String get message =>
      serverMessage ??
      switch (kind) {
        PetLinkFailureKind.notFound => 'No existe una mascota con ese código.',
        PetLinkFailureKind.invalidCode => 'El código debe tener el formato MSC-XXXX.',
        PetLinkFailureKind.clinicInactive =>
          'Tu clínica debe estar activa para vincular mascotas. Completa tu perfil de atención.',
        PetLinkFailureKind.notAllowed => 'Solo las clínicas pueden vincular mascotas.',
        PetLinkFailureKind.tooManyAttempts =>
          'Demasiados intentos. Intenta de nuevo más tarde.',
        PetLinkFailureKind.network => 'No se pudo vincular la mascota. Verifica tu conexión',
        PetLinkFailureKind.notConfigured =>
          'La vinculación no está disponible en esta versión de la app',
        PetLinkFailureKind.unknown => 'No se pudo vincular la mascota. Intenta de nuevo.',
      };

  bool get canRetry =>
      kind == PetLinkFailureKind.network || kind == PetLinkFailureKind.unknown;
}

/// Llama a la Edge Function `vincular-mascota` (semana 3): la clínica escribe
/// el código de paciente que le da el dueño y queda autorizada para ver la
/// mascota y su historial médico.
class PetLinkApi {
  PetLinkApi(this._functions);

  /// null = Supabase no está configurado en este equipo.
  final FunctionsClient? _functions;

  static const _timeout = Duration(seconds: 10);

  Future<LinkedPet> link(String code) async {
    final functions = _functions;
    if (functions == null) {
      throw const PetLinkFailure(PetLinkFailureKind.notConfigured);
    }
    try {
      final response = await functions
          .invoke('vincular-mascota', body: {'codigo': code})
          .timeout(_timeout);
      final data = response.data;
      if (data is! Map) throw const PetLinkFailure(PetLinkFailureKind.unknown);
      return LinkedPet.fromMap(Map<String, dynamic>.from(data));
    } on TimeoutException {
      throw const PetLinkFailure(PetLinkFailureKind.network);
    } on SocketException {
      throw const PetLinkFailure(PetLinkFailureKind.network);
    } on http.ClientException {
      throw const PetLinkFailure(PetLinkFailureKind.network);
    } on FunctionException catch (e) {
      final error = e.details is Map ? (e.details as Map)['error'] : null;
      final message = error is Map ? error['message'] as String? : null;
      throw PetLinkFailure(
        switch (e.status) {
          404 => PetLinkFailureKind.notFound,
          400 => PetLinkFailureKind.invalidCode,
          412 => PetLinkFailureKind.clinicInactive,
          403 || 401 => PetLinkFailureKind.notAllowed,
          429 => PetLinkFailureKind.tooManyAttempts,
          _ => PetLinkFailureKind.unknown,
        },
        serverMessage: message,
      );
    }
  }
}
