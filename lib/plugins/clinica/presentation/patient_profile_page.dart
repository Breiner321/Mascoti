import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/medical_records_providers.dart';
import '../../../core/domain/medical_record.dart';
import '../../../core/domain/pet.dart';
import '../../../core/theme/app_theme.dart';
import '../clinica_routes.dart';
import 'centered_message.dart';
import 'clinic_providers.dart';
import 'patient_avatar.dart';
import 'record_card.dart';

/// Perfil de un paciente para la clínica: datos de la mascota (solo
/// lectura, alergias y condiciones resaltadas), su historial médico y el
/// botón "Nueva consulta".
class PatientProfilePage extends ConsumerWidget {
  const PatientProfilePage({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId ?? '';
    final pet = ref.watch(patientProvider(petId));
    final hasPet = pet.value != null;

    return Scaffold(
      appBar: AppBar(title: Text(pet.value?.nombre ?? 'Paciente')),
      floatingActionButton: hasPet
          ? FloatingActionButton.extended(
              onPressed: () => context.push(ClinicaRoutes.newRecord(petId)),
              icon: const Icon(Icons.add),
              label: const Text('Nueva consulta'),
            )
          : null,
      body: switch (pet) {
        AsyncData(value: final Pet p) => _Profile(pet: p, clinicId: clinicId),
        AsyncData() => const CenteredMessage(
            icon: Icons.lock_outline,
            text: 'Ya no tienes acceso a esta mascota',
            detail: 'El dueño quitó la autorización o la mascota fue eliminada.',
          ),
        AsyncError() => CenteredMessage(
            icon: Icons.cloud_off,
            text: 'No se pudo cargar el paciente.',
            action: FilledButton(
              onPressed: () => ref.invalidate(patientProvider(petId)),
              child: const Text('Reintentar'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.pet, required this.clinicId});

  final Pet pet;
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(recordsClockProvider)();
    final owner = ref.watch(ownerNamesProvider(clinicId)).value?[pet.id] ?? '';
    final records = ref.watch(medicalRecordsProvider(pet.id));

    return ListView(
      // Espacio abajo para que el botón flotante no tape la última consulta.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Row(
          children: [
            PatientAvatar(photoPath: pet.fotoPath, size: 80),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.nombre,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(pet.summary(now), style: theme.textTheme.bodyLarge),
                  if (pet.codigoPaciente != null)
                    Text(
                      pet.codigoPaciente!,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (pet.alergias.isNotEmpty) _AlertList(title: 'Alergias', items: pet.alergias),
        if (pet.condiciones.isNotEmpty) _AlertList(title: 'Condiciones', items: pet.condiciones),
        _DataCard(rows: [
          ('Dueño', owner.isEmpty ? 'Sin registrar' : owner),
          ('Raza', (pet.raza?.isNotEmpty ?? false) ? pet.raza! : 'Sin registrar'),
          ('Sexo', pet.sexoTexto),
          (
            'Nacimiento',
            pet.fechaNacimiento == null
                ? 'Sin registrar'
                : DateFormat("d 'de' MMMM 'de' y", 'es').format(pet.fechaNacimiento!),
          ),
          if (pet.contactoEmergencia != null)
            (
              'Emergencia',
              '${pet.contactoEmergencia!.nombre} · ${pet.contactoEmergencia!.telefono}',
            ),
        ]),
        const SizedBox(height: 24),
        Text('Historial médico', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        switch (records) {
          AsyncData(:final value) when value.isEmpty => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CenteredMessage(
                icon: Icons.history_edu_outlined,
                text: 'Esta mascota aún no tiene historial médico registrado',
                detail: 'Toca "Nueva consulta" para registrar la primera.',
              ),
            ),
          AsyncData(:final value) => Column(
              children: [
                for (final MedicalRecord r in value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RecordCard(
                      key: ValueKey(r.id),
                      record: r,
                      ownClinicId: clinicId,
                      now: now,
                      onTap: () => context.push(ClinicaRoutes.record(pet.id, r.id)),
                    ),
                  ),
              ],
            ),
          AsyncError() => CenteredMessage(
              icon: Icons.cloud_off,
              text: 'No se pudo cargar el historial.',
              action: FilledButton(
                onPressed: () => ref.invalidate(medicalRecordsProvider(pet.id)),
                child: const Text('Reintentar'),
              ),
            ),
          _ => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        },
      ],
    );
  }
}

/// Alergias o condiciones en rojo, para que se vean antes de atender.
class _AlertList extends StatelessWidget {
  const _AlertList({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.sosContainer,
        border: Border.all(color: AppColors.sosBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.sos, size: 20),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.sos, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                Chip(
                  label: Text(item),
                  labelStyle: const TextStyle(color: AppColors.onPrimary),
                  backgroundColor: AppColors.sos,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
