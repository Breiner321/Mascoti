import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/pet.dart';
import '../../../../core/theme/app_theme.dart';
import '../pets_providers.dart';

/// Perfil de la mascota: código de paciente que el dueño le da a su
/// veterinaria y clínicas con acceso al historial, con opción de revocar.
class PatientAccessCard extends ConsumerWidget {
  const PatientAccessCard({super.key, required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final code = pet.codigoPaciente != null
        ? AsyncData<String>(pet.codigoPaciente!)
        : ref.watch(patientCodeProvider(pet));

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Código de paciente',
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Dáselo a tu veterinaria para que pueda ver y registrar el historial '
            'de ${pet.nombre}.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          switch (code) {
            AsyncData(:final value) => Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      value,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Copiar código',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Código copiado')),
                      );
                    },
                  ),
                ],
              ),
            AsyncError() => Row(
                children: [
                  const Expanded(
                    child: Text('No se pudo generar el código. Verifica tu conexión'),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(patientCodeProvider(pet)),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            _ => const LinearProgressIndicator(),
          },
          const SizedBox(height: 16),
          Text('Clínicas con acceso',
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (pet.clinicasAutorizadas.isEmpty)
            Text(
              'Ninguna clínica tiene acceso todavía.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            )
          else
            for (final clinicId in pet.clinicasAutorizadas)
              _AuthorizedClinicTile(pet: pet, clinicId: clinicId),
        ],
      ),
    );
  }
}

class _AuthorizedClinicTile extends ConsumerWidget {
  const _AuthorizedClinicTile({required this.pet, required this.clinicId});

  final Pet pet;
  final String clinicId;

  Future<void> _revoke(BuildContext context, WidgetRef ref, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar acceso'),
        content: Text(
          '$name ya no podrá ver a ${pet.nombre} ni su historial médico. '
          'Para volver a darle acceso, comparte de nuevo el código.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar acceso'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(petsRepositoryProvider).revokeClinic(pet.id, clinicId);
      messenger.showSnackBar(SnackBar(content: Text('$name ya no tiene acceso')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo quitar el acceso. Verifica tu conexión')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(authorizedClinicProvider(clinicId));
    final name = clinic.value?.nombre ?? 'Clínica';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.local_hospital_outlined, color: AppColors.primary),
      title: Text(clinic.isLoading ? 'Cargando…' : name),
      subtitle: clinic.value == null ? null : Text(clinic.value!.direccion),
      trailing: TextButton(
        onPressed: () => _revoke(context, ref, name),
        child: const Text('Quitar'),
      ),
    );
  }
}
