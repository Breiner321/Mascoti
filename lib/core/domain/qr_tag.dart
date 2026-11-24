import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Qué ve quien escanea la placa (`qrTags.mostrar`). El nombre, la especie
/// y la foto de la mascota se muestran siempre; el resto lo elige el dueño.
@immutable
class QrTagDisplay {
  const QrTagDisplay({
    this.nombreDueno = true,
    this.telefono = true,
    this.alergias = true,
    this.mensaje = '',
  });

  factory QrTagDisplay.fromMap(Map<String, dynamic> map) => QrTagDisplay(
        nombreDueno: map['nombreDueno'] == true,
        telefono: map['telefono'] == true,
        alergias: map['alergias'] == true,
        mensaje: map['mensaje'] as String? ?? '',
      );

  /// Máximo del mensaje (igual que firestore.rules).
  static const maxMensaje = 200;

  final bool nombreDueno;
  final bool telefono;
  final bool alergias;

  /// Mensaje opcional para quien la encuentre ("Recompensa", "Toma medicina").
  final String mensaje;

  Map<String, dynamic> toMap() => {
        'nombreDueno': nombreDueno,
        'telefono': telefono,
        'alergias': alergias,
        if (mensaje.trim().isNotEmpty) 'mensaje': mensaje.trim(),
      };

  QrTagDisplay copyWith({bool? nombreDueno, bool? telefono, bool? alergias, String? mensaje}) =>
      QrTagDisplay(
        nombreDueno: nombreDueno ?? this.nombreDueno,
        telefono: telefono ?? this.telefono,
        alergias: alergias ?? this.alergias,
        mensaje: mensaje ?? this.mensaje,
      );

  /// RF-17: la placa necesita foto de la mascota y al menos una forma de
  /// contacto (el teléfono del dueño o un mensaje). Devuelve el problema o
  /// null si se puede guardar.
  String? validate({required bool hasPhoto, required bool ownerHasPhone}) {
    if (!hasPhoto) return 'Agrega una foto de tu mascota para crear la placa.';
    if (mensaje.trim().length > maxMensaje) {
      return 'El mensaje no puede superar $maxMensaje caracteres.';
    }
    final contact = (telefono && ownerHasPhone) || mensaje.trim().isNotEmpty;
    if (!contact) {
      return ownerHasPhone
          ? 'Muestra tu teléfono o escribe un mensaje para que puedan contactarte.'
          : 'Escribe un mensaje de contacto o agrega tu teléfono en Perfil.';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is QrTagDisplay &&
      other.nombreDueno == nombreDueno &&
      other.telefono == telefono &&
      other.alergias == alergias &&
      other.mensaje == mensaje;

  @override
  int get hashCode => Object.hash(nombreDueno, telefono, alergias, mensaje);
}

/// Documento `qrTags/{qrId}` (RF-17). Solo su dueño lo lee y lo cambia; la
/// página pública usa la Edge Function `placa-publica`. No se borra.
@immutable
class QrTag {
  const QrTag({
    required this.id,
    required this.petId,
    required this.ownerUid,
    required this.activo,
    required this.mostrar,
    this.createdAt,
  });

  factory QrTag.fromMap(String id, Map<String, dynamic> map) => QrTag(
        id: id,
        petId: map['petId'] as String? ?? '',
        ownerUid: map['ownerUid'] as String? ?? '',
        activo: map['activo'] == true,
        mostrar: QrTagDisplay.fromMap(Map<String, dynamic>.from((map['mostrar'] as Map?) ?? const {})),
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );

  final String id;
  final String petId;
  final String ownerUid;
  final bool activo;
  final QrTagDisplay mostrar;
  final DateTime? createdAt;

  /// Letras y dígitos sin ambigüedad visual para un id aleatorio.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

  /// Largo del id: 12 caracteres (≈ 70 bits), difícil de adivinar.
  static const idLength = 12;

  static String newId([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(idLength, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  @override
  bool operator ==(Object other) =>
      other is QrTag &&
      other.id == id &&
      other.petId == petId &&
      other.ownerUid == ownerUid &&
      other.activo == activo &&
      other.mostrar == mostrar &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, petId, ownerUid, activo, mostrar, createdAt);
}

/// "3001234567" → "300 *** **67", igual que `enmascararTelefono` de
/// `supabase/functions/_shared/placa.ts` (vista previa de la placa).
String maskPhone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length < 6) return '*' * max(d.length, 3);
  if (d.length == 10) return '${d.substring(0, 3)} *** **${d.substring(8)}';
  return '${d.substring(0, 3)} ${'*' * (d.length - 5)}${d.substring(d.length - 2)}';
}
