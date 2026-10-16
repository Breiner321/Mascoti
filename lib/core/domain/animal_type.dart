/// Tipos de animales que atiende una clínica (`clinics.tiposAnimales`, RF-04).
/// [value] es lo que se guarda en Firestore; [label] el texto de la UI.
enum AnimalType {
  perros('perros', 'Perros'),
  gatos('gatos', 'Gatos'),
  aves('aves', 'Aves'),
  roedores('roedores', 'Roedores'),
  reptiles('reptiles', 'Reptiles'),
  granja('granja', 'Animales de granja'),
  exoticos('exoticos', 'Exóticos');

  const AnimalType(this.value, this.label);

  final String value;
  final String label;

  /// null si el valor no es válido (se ignora al leer listas).
  static AnimalType? fromValue(Object? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }

  /// Lista de Firestore → enums, descartando valores desconocidos.
  static List<AnimalType> listFrom(Object? raw) => raw is List
      ? raw.map(fromValue).whereType<AnimalType>().toList(growable: false)
      : const [];
}
