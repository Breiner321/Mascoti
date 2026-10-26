import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/appointments_providers.dart';
import '../../../../core/kernel/plugin_registry.dart';
import '../../../../core/theme/app_theme.dart';
import 'booking_logic.dart';
import 'owner_routes.dart';

/// Paso previo de "Agendar cita" cuando no viene la clínica (home o pestaña
/// Citas): "Tus clínicas" (las de citas anteriores) o buscar en el mapa.
class ClinicPickerView extends ConsumerWidget {
  const ClinicPickerView({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final uid = ref.watch(currentUserProvider)?.uid;
    final hasMap = ref.watch(pluginRegistryProvider).hasRoute(OwnerBookingRoutes.map);
    final appointments = uid == null
        ? const AsyncData(<Never>[])
        : ref.watch(ownerAppointmentsProvider(uid));

    final mapButton = hasMap
        ? OutlinedButton.icon(
            // El mapa es una pestaña (shell): se cambia de pestaña con `go`;
            // un `push` desde esta pantalla completa rompe el navegador.
            onPressed: () => context.go(OwnerBookingRoutes.map),
            icon: const Icon(Icons.location_on_outlined),
            label: const Text('Buscar en el mapa'),
          )
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('¿En qué clínica?',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Text('TUS CLÍNICAS',
            style: textTheme.labelMedium
                ?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        switch (appointments) {
          AsyncData(:final value) when value.isEmpty => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aún no tienes clínicas. Búscalas en el mapa para agendar tu primera cita.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ),
          AsyncData(:final value) => Column(
              children: [
                for (final clinic in BookingLogic.recentClinics(value))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.local_hospital_outlined,
                            color: AppColors.primary),
                        title: Text(clinic.nombre.isEmpty ? 'Clínica' : clinic.nombre),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onPick(clinic.id),
                      ),
                    ),
                  ),
              ],
            ),
          AsyncError() => Column(
              children: [
                const Text('No pudimos cargar tus clínicas. Verifica tu conexión.'),
                TextButton(
                  onPressed: () => ref.invalidate(ownerAppointmentsProvider(uid!)),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          _ => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        },
        if (mapButton != null) ...[const SizedBox(height: 16), mapButton],
      ],
    );
  }
}
