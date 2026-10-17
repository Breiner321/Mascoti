import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'animal_type.dart';

/// Especie de la mascota (`pets.especie`). Corresponde 1 a 1 con los
/// [AnimalType] que atiende una clínica (RF-04), para filtrar clínicas.
enum PetSpecies {
  perro('perro', 'Perro', AnimalType.perros),
  gato('gato', 'Gato', AnimalType.gatos),
  ave('ave', 'Ave', AnimalType.aves),
  roedor('roedor', 'Roedor', AnimalType.roedores),
  reptil('reptil', 'Reptil', AnimalType.reptiles),
  granja('granja', 'Animal de granja', AnimalType.granja),
  exotico('exotico', 'Exótico', AnimalType.exoticos);

  const PetSpecies(this.value, this.label, this.animalType);

  final String value;
  final String label;

  /// Tipo que una clínica debe atender para recibir a esta mascota.
  final AnimalType animalType;

  /// Un valor desconocido se trata como exótico.
  static PetSpecies fromValue(Object? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return exotico;
  }
}

/// `pets.sexo`. Algunas especies (exóticos, aves jóvenes, reptiles) no
/// tienen el sexo determinado; con [otro] se especifica en `sexoDetalle`.
enum PetSex {
  macho('macho', 'Macho'),
  hembra('hembra', 'Hembra'),
  indeterminado('indeterminado', 'Indeterminado'),
  otro('otro', 'Otro (especifique)');

  const PetSex(this.value, this.label);

  final String value;
  final String label;

  static PetSex? fromValue(Object? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return null;
  }
}

/// `pets.contactoEmergencia` (RF-17: se muestra en la placa QR).
@immutable
class EmergencyContact {
  const EmergencyContact({required this.nombre, required this.telefono});

  factory EmergencyContact.fromMap(Map<String, dynamic> map) => EmergencyContact(
        nombre: map['nombre'] as String? ?? '',
        telefono: map['telefono'] as String? ?? '',
      );

  final String nombre;
  final String telefono;

  Map<String, dynamic> toMap() => {'nombre': nombre, 'telefono': telefono};

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact && other.nombre == nombre && other.telefono == telefono;

  @override
  int get hashCode => Object.hash(nombre, telefono);
}

/// Documento `pets/{petId}` (soporte para RF-08, RF-14, RF-17, RF-18).
/// Lo usan varios plugins (mascotas, reservas, utilidades), por eso vive en
/// el core.
@immutable
class Pet {
  const Pet({
    required this.id,
    required this.ownerUid,
    required this.nombre,
    required this.especie,
    this.raza,
    this.sexo,
    this.sexoDetalle,
    this.fechaNacimiento,
    this.fotoPath,
    this.alergias = const [],
    this.condiciones = const [],
    this.contactoEmergencia,
    this.createdAt,
  });

  factory Pet.fromMap(String id, Map<String, dynamic> map) => Pet(
        id: id,
        ownerUid: map['ownerUid'] as String? ?? '',
        nombre: map['nombre'] as String? ?? '',
        especie: PetSpecies.fromValue(map['especie']),
        raza: map['raza'] as String?,
        sexo: PetSex.fromValue(map['sexo']),
        sexoDetalle: map['sexoDetalle'] as String?,
        fechaNacimiento: (map['fechaNacimiento'] as Timestamp?)?.toDate(),
        fotoPath: map['fotoPath'] as String?,
        alergias: _strings(map['alergias']),
        condiciones: _strings(map['condiciones']),
        contactoEmergencia: map['contactoEmergencia'] is Map
            ? EmergencyContact.fromMap(
                Map<String, dynamic>.from(map['contactoEmergencia'] as Map))
            : null,
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );

  final String id;
  final String ownerUid;
  final String nombre;
  final PetSpecies especie;
  final String? raza;
  final PetSex? sexo;

  /// Texto libre cuando [sexo] es [PetSex.otro] (máx. 30 caracteres).
  final String? sexoDetalle;

  /// Texto para mostrar: "Hembra", "Otro: hermafrodita", "Sin registrar".
  String get sexoTexto => switch (sexo) {
        null => 'Sin registrar',
        PetSex.otro => (sexoDetalle?.trim().isNotEmpty ?? false)
            ? 'Otro: ${sexoDetalle!.trim()}'
            : 'Otro',
        final s => s.label,
      };
  final DateTime? fechaNacimiento;

  /// Ruta de la foto en el bucket `mascotas` de Supabase Storage:
  /// `{ownerUid}/{petId}/foto.jpg|png` (ver StorageRepository.petPhotoPath).
  /// Para mostrarla se pide un enlace temporal con StorageRepository.signedUrl.
  final String? fotoPath;
  final List<String> alergias;
  final List<String> condiciones;
  final EmergencyContact? contactoEmergencia;
  final DateTime? createdAt;

  static List<String> _strings(Object? raw) =>
      raw is List ? raw.whereType<String>().toList(growable: false) : const [];

  Map<String, dynamic> toMap() => {
        'ownerUid': ownerUid,
        'nombre': nombre,
        'especie': especie.value,
        'raza': raza,
        'sexo': sexo?.value,
        // Solo se guarda con sexo "otro".
        'sexoDetalle': sexo == PetSex.otro ? sexoDetalle : null,
        'fechaNacimiento':
            fechaNacimiento == null ? null : Timestamp.fromDate(fechaNacimiento!),
        'fotoPath': fotoPath,
        'alergias': alergias,
        'condiciones': condiciones,
        'contactoEmergencia': contactoEmergencia?.toMap(),
        'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      };

  Pet copyWith({
    String? nombre,
    PetSpecies? especie,
    String? raza,
    PetSex? sexo,
    String? sexoDetalle,
    DateTime? fechaNacimiento,
    String? fotoPath,
    List<String>? alergias,
    List<String>? condiciones,
    EmergencyContact? contactoEmergencia,
  }) =>
      Pet(
        id: id,
        ownerUid: ownerUid,
        nombre: nombre ?? this.nombre,
        especie: especie ?? this.especie,
        raza: raza ?? this.raza,
        sexo: sexo ?? this.sexo,
        sexoDetalle: sexoDetalle ?? this.sexoDetalle,
        fechaNacimiento: fechaNacimiento ?? this.fechaNacimiento,
        fotoPath: fotoPath ?? this.fotoPath,
        alergias: alergias ?? this.alergias,
        condiciones: condiciones ?? this.condiciones,
        contactoEmergencia: contactoEmergencia ?? this.contactoEmergencia,
        createdAt: createdAt,
      );

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
  String summary(DateTime now) =>
      [especie.label, ageLabel(now)].whereType<String>().join(' · ');

  @override
  bool operator ==(Object other) =>
      other is Pet &&
      other.id == id &&
      other.ownerUid == ownerUid &&
      other.nombre == nombre &&
      other.especie == especie &&
      other.raza == raza &&
      other.sexo == sexo &&
      other.sexoDetalle == sexoDetalle &&
      other.fechaNacimiento == fechaNacimiento &&
      other.fotoPath == fotoPath &&
      listEquals(other.alergias, alergias) &&
      listEquals(other.condiciones, condiciones) &&
      other.contactoEmergencia == contactoEmergencia &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        ownerUid,
        nombre,
        especie,
        raza,
        sexo,
        sexoDetalle,
        fechaNacimiento,
        fotoPath,
        Object.hashAll(alergias),
        Object.hashAll(condiciones),
        contactoEmergencia,
        createdAt,
      );
}
