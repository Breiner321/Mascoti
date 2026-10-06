import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/kernel/plugin_registry.dart';
import 'home_shortcuts.dart';
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
    final registry = ref.watch(pluginRegistryProvider);
    final pets = ref.watch(myPetsProvider);

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
            onRetry: () => ref.invalidate(myPetsProvider),
            onAddPet: open(HomeShortcuts.newPet),
            onOpenList: open(HomeShortcuts.petList),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: NextAppointmentCard(
                    onSchedule: open(HomeShortcuts.schedule),
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
            childAspectRatio: 1.45,
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
            height: 88,
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
