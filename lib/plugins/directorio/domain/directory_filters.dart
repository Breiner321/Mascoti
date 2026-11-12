import 'package:flutter/foundation.dart';

import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/domain/animal_type.dart';
import '../../../core/domain/clinic_service.dart';

/// Filtros del directorio (RF-09 paso 8): los chips del mockup más el radio.
/// Es lógica pura: se convierte en [ClinicFilters] del core para la consulta.
@immutable
class DirectoryFilters {
  const DirectoryFilters({
    this.animalTypes = const {},
    this.service,
    this.emergencies = false,
    this.radiusKm = defaultRadiusKm,
    this.onlyAllies = false,
  });

  /// Radio del control deslizante (RF-09: "ampliar el radio de búsqueda").
  static const minRadiusKm = 5.0;
  static const maxRadiusKm = 50.0;
  static const defaultRadiusKm = ClinicsGeoRepository.defaultRadiusKm;

  /// Opciones de distancia del chip "Distancia".
  static const radiusOptions = [5.0, 10.0, 20.0, 50.0];

  final Set<AnimalType> animalTypes;
  final ServiceCategory? service;

  /// Chip "24 horas": clínicas con atención de emergencias (no hay un campo
  /// de horario 24 h; `atencionEmergencias` es lo que usa también el SOS).
  final bool emergencies;
  final double radiusKm;

  /// Chip "Solo aliados" (Cambio 4): oculta las veterinarias de
  /// OpenStreetMap que aún no usan Mascoti.
  final bool onlyAllies;

  /// Radio dentro de 5–50 km, redondeado al kilómetro.
  static double clampRadius(double km) =>
      km.clamp(minRadiusKm, maxRadiusKm).roundToDouble();

  /// Filtros de la consulta (el radio va aparte, en NearbyQuery).
  ClinicFilters toClinicFilters() => ClinicFilters(
        animalTypes: animalTypes,
        serviceCategory: service,
        onlyEmergencies: emergencies,
      );

  /// Cuántos filtros (sin contar el radio) están activos.
  int get activeCount =>
      (animalTypes.isEmpty ? 0 : 1) +
      (service == null ? 0 : 1) +
      (emergencies ? 1 : 0) +
      (onlyAllies ? 1 : 0);

  /// Filtros que solo pueden aplicarse a los aliados: las veterinarias de
  /// OpenStreetMap no tienen especies, servicios ni emergencias en Mascoti.
  bool get hasAllyOnlyFilters =>
      animalTypes.isNotEmpty || service != null || emergencies;

  bool get hasFilters => activeCount > 0;

  DirectoryFilters toggleAnimal(AnimalType type) => _copy(
        animalTypes: animalTypes.contains(type)
            ? ({...animalTypes}..remove(type))
            : {...animalTypes, type},
      );

  /// Elige un servicio; elegir el mismo lo quita.
  DirectoryFilters toggleService(ServiceCategory category) => DirectoryFilters(
        animalTypes: animalTypes,
        service: service == category ? null : category,
        emergencies: emergencies,
        radiusKm: radiusKm,
        onlyAllies: onlyAllies,
      );

  DirectoryFilters toggleEmergencies() => _copy(emergencies: !emergencies);

  DirectoryFilters toggleOnlyAllies() => _copy(onlyAllies: !onlyAllies);

  DirectoryFilters withRadius(double km) => _copy(radiusKm: clampRadius(km));

  /// Quita los filtros y conserva el radio.
  DirectoryFilters cleared() => DirectoryFilters(radiusKm: radiusKm);

  DirectoryFilters _copy(
          {Set<AnimalType>? animalTypes,
          bool? emergencies,
          double? radiusKm,
          bool? onlyAllies}) =>
      DirectoryFilters(
        animalTypes: animalTypes ?? this.animalTypes,
        service: service,
        emergencies: emergencies ?? this.emergencies,
        radiusKm: radiusKm ?? this.radiusKm,
        onlyAllies: onlyAllies ?? this.onlyAllies,
      );

  @override
  bool operator ==(Object other) =>
      other is DirectoryFilters &&
      setEquals(other.animalTypes, animalTypes) &&
      other.service == service &&
      other.emergencies == emergencies &&
      other.radiusKm == radiusKm &&
      other.onlyAllies == onlyAllies;

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered(animalTypes), service, emergencies, radiusKm, onlyAllies);
}

/// "850 m" o "2,3 km".
String distanceLabel(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  final text = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return '${text.replaceAll('.', ',')} km';
}
