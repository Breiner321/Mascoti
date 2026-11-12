import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/data/medical_records_providers.dart';
import '../../../../../core/domain/chat.dart';
import '../../../../../core/domain/medical_record.dart';
import '../../../../../core/domain/pet.dart';
import '../../../../../core/theme/app_theme.dart';
import '../chat_ui_providers.dart';

/// Adjunto del historial elegido para enviar al chat.
@immutable
class HistorySelection {
  const HistorySelection({required this.pet, required this.record, required this.attachment});

  final Pet pet;
  final MedicalRecord record;
  final RecordAttachment attachment;
}

/// "Desde el historial" (RF-16, solo la clínica): elige una mascota del
/// dueño de la conversación, una de sus consultas y uno de sus adjuntos
/// (radiografía, examen…). Devuelve la [HistorySelection] o null.
class HistoryAttachmentPage extends ConsumerStatefulWidget {
  const HistoryAttachmentPage({super.key, required this.chat});

  final Chat chat;

  @override
  ConsumerState<HistoryAttachmentPage> createState() => _HistoryAttachmentPageState();
}

class _HistoryAttachmentPageState extends ConsumerState<HistoryAttachmentPage> {
  String? _petId;

  @override
  Widget build(BuildContext context) {
    final pets = ref.watch(linkedPetsProvider(widget.chat.clinicId));
    return Scaffold(
      appBar: AppBar(title: const Text('Desde el historial')),
      body: switch (pets) {
        AsyncData(:final value) => _body(_ownerPets(value)),
        AsyncError() => _Message(
            icon: Icons.cloud_off,
            text: 'No se pudieron cargar las mascotas.',
            action: FilledButton(
              onPressed: () => ref.invalidate(linkedPetsProvider(widget.chat.clinicId)),
              child: const Text('Reintentar'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  /// Mascotas de este dueño vinculadas a la clínica; primero las del chat.
  List<Pet> _ownerPets(List<Pet> all) {
    final own = [for (final p in all) if (p.ownerUid == widget.chat.ownerUid) p];
    final inChat = widget.chat.petIds;
    own.sort((a, b) {
      final ia = inChat.contains(a.id) ? 0 : 1;
      final ib = inChat.contains(b.id) ? 0 : 1;
      return ia != ib ? ia - ib : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return own;
  }

  Widget _body(List<Pet> pets) {
    if (pets.isEmpty) {
      return const _Message(
        icon: Icons.pets,
        text: 'Este dueño no tiene mascotas vinculadas a tu clínica.',
      );
    }
    final selected = pets.firstWhere((p) => p.id == _petId, orElse: () => pets.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pets.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                for (final p in pets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.nombre),
                      selected: p.id == selected.id,
                      onSelected: (_) => setState(() => _petId = p.id),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(child: _Records(pet: selected)),
      ],
    );
  }
}

class _Records extends ConsumerWidget {
  const _Records({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(medicalRecordsProvider(pet.id));
    return switch (records) {
      AsyncData(:final value) => () {
          final withFiles = [for (final r in value) if (r.adjuntos.isNotEmpty) r];
          if (withFiles.isEmpty) {
            return _Message(
              icon: Icons.folder_off_outlined,
              text: '${pet.nombre} no tiene consultas con archivos adjuntos.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Elige una consulta y el archivo que quieres enviar.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              for (final r in withFiles)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    key: PageStorageKey(r.id),
                    initiallyExpanded: withFiles.length == 1,
                    title: Text(DateFormat("d 'de' MMMM 'de' y", 'es').format(r.fecha)),
                    subtitle: Text(
                      [r.diagnostico, r.clinicNombre].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    children: [
                      for (final a in r.adjuntos)
                        ListTile(
                          leading: Icon(
                            a.tipo == AttachmentType.pdf
                                ? Icons.picture_as_pdf_outlined
                                : Icons.image_outlined,
                            color: AppColors.primary,
                          ),
                          title: Text(a.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.send_outlined),
                          onTap: () => Navigator.of(context).pop(
                            HistorySelection(pet: pet, record: r, attachment: a),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        }(),
      AsyncError() => _Message(
          icon: Icons.cloud_off,
          text: 'No se pudo cargar el historial.',
          action: FilledButton(
            onPressed: () => ref.invalidate(medicalRecordsProvider(pet.id)),
            child: const Text('Reintentar'),
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
