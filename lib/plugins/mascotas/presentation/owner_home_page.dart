import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/kernel/plugin_registry.dart';
import '../mascotas_routes.dart';
import 'home_shortcuts.dart';
import 'next_appointment_provider.dart';
import 'pets_providers.dart';
import 'widgets/health_card_tile.dart';
import 'widgets/next_appointment_card.dart';
import 'widgets/pet_summary_card.dart';
import 'widgets/section_title.dart';
import 'widgets/service_shortcut.dart';
import 'widgets/shortcut_tile.dart';

/// Home del dueño (mockup VISTA CLIENTE, primera pantalla).
///
/// Los accesos a otros módulos se resuelven por id de plugin + ruta con
/// [PluginRegistry]; los que aún no existen se muestran como "Próximamente".
class OwnerHomePage extends ConsumerWidget {
  const OwnerHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final registry = ref.watch(pluginRegistryProvider);
    final pets = ref.watch(myPetsProvider);
    final next = ref.watch(nextAppointmentProvider);

    VoidCallback? open(HomeShortcut shortcut) => shortcut.isAvailable(registry)
        ? () => context.push(shortcut.path)
        : null;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myPetsProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PetSummaryCard(
            pets: pets,
            selectedPetId: ref.watch(selectedPetIdProvider),
            onRetry: () => ref.invalidate(myPetsProvider),
            onAddPet: open(HomeShortcuts.newPet),
            onOpenPet: (pet) => context.push(MascotasRoutes.profile(pet.id)),
            onSelectPet: (id) => ref.read(selectedPetIdProvider.notifier).select(id),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: NextAppointmentCard(
                    onSchedule: open(HomeShortcuts.schedule),
                    appointment: next,
                    onOpen: next == null || !registry.hasRoute('/reservas/${next.id}')
                        ? null
                        : () => context.push('/reservas/${next.id}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: HealthCardTile(onTap: open(HomeShortcuts.healthCard)),
                ),
              ],
            ),
          ),
          const SectionTitle('Accesos'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Cambio 3: las tarjetas crecen con el tamaño del texto.
            childAspectRatio: 1.45 / textScale,
            children: [
              for (final shortcut in HomeShortcuts.access)
                ShortcutTile(
                  label: shortcut.label,
                  icon: shortcut.icon,
                  emergency: shortcut == HomeShortcuts.emergency,
                  onTap: open(shortcut),
                ),
            ],
          ),
          const SectionTitle('Servicios'),
          SizedBox(
            height: 48 + 40 * textScale,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: HomeShortcuts.services.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final service = HomeShortcuts.services[i];
                return ServiceShortcut(
                  label: service.label,
                  icon: service.icon,
                  onTap: open(service),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
