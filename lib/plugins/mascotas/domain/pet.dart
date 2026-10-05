import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Documento `pets/{petId}` (ver docs/modelo-datos.md).
@immutable
class Pet {
  const Pet({
    required this.id,
    required this.ownerUid,
    required this.nombre,
    required this.especie,
    this.raza,
    this.sexo,
    this.fechaNacimiento,
    this.fotoUrl,
    this.createdAt,
  });

  factory Pet.fromMap(String id, Map<String, dynamic> map) => Pet(
        id: id,
        ownerUid: map['ownerUid'] as String? ?? '',
        nombre: map['nombre'] as String? ?? '',
        especie: map['especie'] as String? ?? '',
        raza: map['raza'] as String?,
        sexo: map['sexo'] as String?,
        fechaNacimiento: (map['fechaNacimiento'] as Timestamp?)?.toDate(),
        fotoUrl: map['fotoUrl'] as String?,
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );

  final String id;
  final String ownerUid;
  final String nombre;
  final String especie;
  final String? raza;
  final String? sexo;
  final DateTime? fechaNacimiento;
  final String? fotoUrl;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'ownerUid': ownerUid,
        'nombre': nombre,
        'especie': especie,
        'raza': raza,
        'sexo': sexo,
        'fechaNacimiento':
            fechaNacimiento == null ? null : Timestamp.fromDate(fechaNacimiento!),
        'fotoUrl': fotoUrl,
        'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      };

  /// Edad para la UI: "3 años", "1 año", "5 meses" o null si no se conoce.
  String? ageLabel(DateTime now) {
    final birth = fechaNacimiento;
    if (birth == null || birth.isAfter(now)) return null;
    var months = (now.year - birth.year) * 12 + now.month - birth.month;
    if (now.day < birth.day) months--;
    if (months < 12) {
      if (months <= 0) return 'Menos de 1 mes';
      return months == 1 ? '1 mes' : '$months meses';
    }
    final years = months ~/ 12;
    return years == 1 ? '1 año' : '$years años';
  }

  /// "Perro · 3 años" (mockup VISTA CLIENTE).
  String summary(DateTime now) {
    final species = especie.isEmpty
        ? ''
        : '${especie[0].toUpperCase()}${especie.substring(1)}';
    return [species, ageLabel(now)]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' · ');
  }
}
