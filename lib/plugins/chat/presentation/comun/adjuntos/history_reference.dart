import 'package:flutter/foundation.dart';

/// `referenciaHistorialId` de un mensaje (RF-16): `"{petId}/{recordId}"`,
/// el registro del historial médico del que viene el adjunto. Con el petId
/// cada lado muestra `"Del historial médico de <mascota>"`.
@immutable
class HistoryReference {
  const HistoryReference({required this.petId, required this.recordId});

  final String petId;
  final String recordId;

  /// null si [value] es null o no tiene el formato.
  static HistoryReference? parse(String? value) {
    if (value == null) return null;
    final parts = value.split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return HistoryReference(petId: parts[0], recordId: parts[1]);
  }

  String get value => '$petId/$recordId';
}
