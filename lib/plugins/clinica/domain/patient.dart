import 'package:flutter/foundation.dart';

import '../../../core/domain/pet.dart';

/// Mascota vinculada a la clínica, con el nombre de su dueño.
@immutable
class Patient {
  const Patient({required this.pet, this.duenoNombre = ''});

  final Pet pet;

  /// Vacío si se vinculó antes de guardar los nombres.
  final String duenoNombre;

  /// Coincide con la búsqueda por nombre, dueño, código o especie (sin
  /// distinguir mayúsculas ni tildes).
  bool matches(String query) {
    final q = normalize(query.trim());
    if (q.isEmpty) return true;
    return [pet.nombre, duenoNombre, pet.codigoPaciente ?? '', pet.especie.label, pet.raza ?? '']
        .any((text) => normalize(text).contains(q));
  }

  static String normalize(String text) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      buffer.write(i < 0 ? ch : to[i]);
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is Patient && other.pet == pet && other.duenoNombre == duenoNombre;

  @override
  int get hashCode => Object.hash(pet, duenoNombre);
}
