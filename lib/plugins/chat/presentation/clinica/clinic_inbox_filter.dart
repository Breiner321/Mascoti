import 'package:flutter/foundation.dart';

import '../../../../core/domain/chat.dart';
import '../../../../core/domain/pet.dart';

/// Conversación de la bandeja de la clínica con las mascotas del dueño
/// vinculadas a la clínica.
@immutable
class ClinicInboxEntry {
  const ClinicInboxEntry({required this.chat, this.pets = const []});

  final Chat chat;
  final List<Pet> pets;
}

/// Arma la bandeja de la clínica [clinicUid] (RF-15): las conversaciones en
/// el orden en que llegan (último mensaje más reciente primero), cada una
/// con las mascotas del dueño. [query] busca por nombre del dueño o de la
/// mascota (sin distinguir mayúsculas ni tildes); [unreadOnly] deja solo las
/// que tienen mensajes sin leer.
List<ClinicInboxEntry> buildClinicInbox({
  required List<Chat> chats,
  required List<Pet> linkedPets,
  required String clinicUid,
  String query = '',
  bool unreadOnly = false,
}) {
  final byOwner = <String, List<Pet>>{};
  for (final pet in linkedPets) {
    (byOwner[pet.ownerUid] ??= []).add(pet);
  }
  final q = normalizeForSearch(query.trim());
  return [
    for (final chat in chats)
      if (!unreadOnly || chat.unreadFor(clinicUid) > 0)
        if (_entry(chat, byOwner[chat.ownerUid] ?? const []) case final entry
            when q.isEmpty || _matches(entry, q))
          entry,
  ];
}

ClinicInboxEntry _entry(Chat chat, List<Pet> ownerPets) {
  // Primero las mascotas con las que se abrió la conversación.
  final pets = [...ownerPets]..sort((a, b) {
      final ia = chat.petIds.contains(a.id) ? 0 : 1;
      final ib = chat.petIds.contains(b.id) ? 0 : 1;
      return ia != ib ? ia - ib : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
  return ClinicInboxEntry(chat: chat, pets: pets);
}

bool _matches(ClinicInboxEntry entry, String q) =>
    normalizeForSearch(entry.chat.ownerNombre).contains(q) ||
    entry.pets.any((p) => normalizeForSearch(p.nombre).contains(q));

/// Minúsculas y sin tildes, para buscar.
String normalizeForSearch(String text) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final buffer = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    buffer.write(i < 0 ? ch : to[i]);
  }
  return buffer.toString();
}
