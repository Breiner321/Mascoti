import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/medical_records_providers.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/record_timeline_tile.dart';

/// Pestaña "Historial médico" del perfil (RF-08): línea de tiempo de solo
/// lectura, la consulta más reciente arriba. Se actualiza sola cuando una
/// clínica agrega un registro.
class MedicalHistoryTab extends ConsumerWidget {
  const MedicalHistoryTab({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(medicalRecordsProvider(petId));
    return switch (records) {
      AsyncData(:final value) when value.isEmpty => const _EmptyHistory(),
      AsyncData(:final value) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: value.length,
          itemBuilder: (context, i) => RecordTimelineTile(
            key: ValueKey(value[i].id),
            record: value[i],
            isFirst: i == 0,
            isLast: i == value.length - 1,
          ),
        ),
      AsyncError() => _Message(
          icon: Icons.cloud_off,
          text: 'No pudimos cargar el historial médico. Verifica tu conexión.',
          onRetry: () => ref.invalidate(medicalRecordsProvider(petId)),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.medical_information_outlined,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Esta mascota aún no tiene historial médico registrado',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando una clínica con acceso registre una consulta, aparecerá aquí.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, required this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
