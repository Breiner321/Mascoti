import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import 'owner_shop_providers.dart';

/// Elegir la clínica de la tienda: "Tus clínicas" (citas o pedidos) y
/// "Cerca de ti" (aliadas a 10 km, solo si el dueño da su ubicación).
/// Devuelve el id elegido.
Future<String?> showClinicPicker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _ClinicPicker(),
    );

class _ClinicPicker extends ConsumerStatefulWidget {
  const _ClinicPicker();

  @override
  ConsumerState<_ClinicPicker> createState() => _ClinicPickerState();
}

class _ClinicPickerState extends ConsumerState<_ClinicPicker> {
  /// La ubicación se pide solo al tocar "Usar mi ubicación".
  bool _nearby = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final visited = ref.watch(visitedClinicsProvider);
    final nearby = _nearby ? ref.watch(nearbyShopClinicsProvider) : null;

    Widget section(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Semantics(
            header: true,
            child: Text(text,
                style: textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
        );

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Elige una clínica', style: textTheme.titleLarge),
            ),
            section('Tus clínicas'),
            if (visited.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Aquí aparecerán las clínicas donde tengas citas o pedidos.',
                  style:
                      textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              )
            else
              for (final e in visited.entries)
                ListTile(
                  leading: Icon(Icons.local_hospital_outlined,
                      color: AppColors.primary),
                  title: Text(e.value.isEmpty ? 'Clínica' : e.value),
                  onTap: () => Navigator.of(context).pop(e.key),
                ),
            section('Cerca de ti'),
            switch (nearby) {
              null => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _nearby = true),
                      icon: const Icon(Icons.my_location),
                      label: const Text('Usar mi ubicación'),
                    ),
                  ),
                ),
              AsyncData(:final value) when value.isEmpty => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    ref.read(ownerPositionProvider).value == null
                        ? 'Sin tu ubicación solo vemos tus clínicas. Puedes activarla en los ajustes.'
                        : 'No encontramos clínicas aliadas a menos de 10 km.',
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              AsyncData(:final value) => Column(
                  children: [
                    for (final n in value)
                      ListTile(
                        leading: Icon(Icons.place_outlined,
                            color: AppColors.primary),
                        title: Text(n.clinic.nombre),
                        subtitle: Text(
                            '${n.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km'),
                        onTap: () => Navigator.of(context).pop(n.clinic.id),
                      ),
                  ],
                ),
              AsyncError() => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(
                          child: Text('No pudimos buscar clínicas cercanas.')),
                      TextButton(
                        onPressed: () => ref.invalidate(ownerPositionProvider),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              _ => const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
            },
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
