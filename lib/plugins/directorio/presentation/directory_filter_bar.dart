import 'package:flutter/material.dart';

import '../../../core/domain/animal_type.dart';
import '../../../core/domain/clinic_service.dart';
import '../domain/directory_filters.dart';

/// Chips de filtro del mockup (RF-09 paso 8): tipo de animal, servicio,
/// "24 horas" (emergencias) y distancia.
class DirectoryFilterBar extends StatelessWidget {
  const DirectoryFilterBar(
      {super.key, required this.filters, required this.onChanged});

  final DirectoryFilters filters;
  final ValueChanged<DirectoryFilters> onChanged;

  Future<void> _pickAnimals(BuildContext context) async {
    final result = await showModalBottomSheet<DirectoryFilters>(
      context: context,
      showDragHandle: true,
      builder: (context) => _AnimalSheet(filters: filters),
    );
    if (result != null) onChanged(result);
  }

  Future<void> _pickService(BuildContext context) async {
    final picked = await showModalBottomSheet<ServiceCategory>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in ServiceCategory.values)
              ListTile(
                title: Text(c.label),
                trailing: filters.service == c ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(filters.toggleService(picked));
  }

  Future<void> _pickRadius(BuildContext context) async {
    final picked = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final km in DirectoryFilters.radiusOptions)
              ListTile(
                title: Text('Hasta ${km.round()} km'),
                trailing:
                    filters.radiusKm == km ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, km),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(filters.withRadius(picked));
  }

  @override
  Widget build(BuildContext context) {
    final animals = filters.animalTypes;
    final service = filters.service;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FilterChip(
            label: Text(animals.isEmpty
                ? 'Tipo de animal'
                : animals.length == 1
                    ? animals.first.label
                    : '${animals.length} tipos'),
            selected: animals.isNotEmpty,
            onSelected: (_) => _pickAnimals(context),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(service?.label ?? 'Servicios'),
            selected: service != null,
            onSelected: (_) => _pickService(context),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('24 horas'),
            tooltip: 'Clínicas con atención de emergencias',
            selected: filters.emergencies,
            onSelected: (_) => onChanged(filters.toggleEmergencies()),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text('Hasta ${filters.radiusKm.round()} km'),
            selected: filters.radiusKm != DirectoryFilters.defaultRadiusKm,
            onSelected: (_) => _pickRadius(context),
          ),
          if (filters.hasFilters) ...[
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.close, size: 16),
              label: const Text('Quitar filtros'),
              onPressed: () => onChanged(filters.cleared()),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnimalSheet extends StatefulWidget {
  const _AnimalSheet({required this.filters});

  final DirectoryFilters filters;

  @override
  State<_AnimalSheet> createState() => _AnimalSheetState();
}

class _AnimalSheetState extends State<_AnimalSheet> {
  late DirectoryFilters _filters = widget.filters;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Qué animales debe atender?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in AnimalType.values)
                  FilterChip(
                    label: Text(t.label),
                    selected: _filters.animalTypes.contains(t),
                    onSelected: (_) =>
                        setState(() => _filters = _filters.toggleAnimal(t)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _filters),
                child: const Text('Aplicar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
