import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/domain/pet.dart';
import 'coming_soon_badge.dart';
import 'pet_avatar.dart';
import 'pet_selector_sheet.dart';

/// Tarjeta "Mi mascota" del home: cargando, vacío, error y datos. Con varias
/// mascotas muestra la activa ([selectedPetId], o la más reciente) y un
/// selector para cambiarla.
class PetSummaryCard extends StatelessWidget {
  const PetSummaryCard({
    super.key,
    required this.pets,
    required this.onRetry,
    required this.onAddPet,
    this.selectedPetId,
    this.onOpenPet,
    this.onSelectPet,
  });

  final AsyncValue<List<Pet>> pets;
  final VoidCallback onRetry;

  /// null = el registro de mascotas no está disponible.
  final VoidCallback? onAddPet;
  final String? selectedPetId;
  final ValueChanged<Pet>? onOpenPet;
  final ValueChanged<String>? onSelectPet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: switch (pets) {
        AsyncData(:final value) when value.isEmpty => _EmptyPet(onAddPet: onAddPet),
        AsyncData(:final value) => _PetInfo(
            pets: value,
            pet: value.firstWhere(
              (p) => p.id == selectedPetId,
              orElse: () => value.first,
            ),
            onOpen: onOpenPet,
            onSelect: onSelectPet,
            onAddPet: onAddPet,
          ),
        AsyncError() => _PetError(onRetry: onRetry),
        _ => const _PetLoading(),
      },
    );
  }
}

class _PetInfo extends StatelessWidget {
  const _PetInfo({
    required this.pets,
    required this.pet,
    required this.onOpen,
    required this.onSelect,
    required this.onAddPet,
  });

  final List<Pet> pets;
  final Pet pet;
  final ValueChanged<Pet>? onOpen;
  final ValueChanged<String>? onSelect;
  final VoidCallback? onAddPet;

  void _openSelector(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => PetSelectorSheet(
        pets: pets,
        selectedId: pet.id,
        onSelect: (id) => onSelect?.call(id),
        onAddPet: onAddPet,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summary = pet.summary(DateTime.now());
    final open = onOpen;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: open == null ? null : () => open(pet),
            child: Row(
              children: [
                PetAvatar(photoPath: pet.fotoPath),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mi mascota',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                      Text(
                        pet.nombre,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (summary.isNotEmpty)
                        Text(summary,
                            style: textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (pets.length > 1)
          IconButton.filledTonal(
            tooltip: 'Cambiar mascota',
            onPressed: () => _openSelector(context),
            icon: const Icon(Icons.swap_horiz),
          )
        else if (onAddPet != null)
          IconButton.filledTonal(
            tooltip: 'Agregar mascota',
            onPressed: onAddPet,
            icon: const Icon(Icons.add),
          ),
      ],
    );
  }
}

class _EmptyPet extends StatelessWidget {
  const _EmptyPet({required this.onAddPet});

  final VoidCallback? onAddPet;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onAddPet,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          const PetAvatar(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mi mascota',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                Text(
                  'Registra tu primera mascota',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Guarda su especie, edad e historial en un solo lugar.',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                if (onAddPet == null) ...[
                  const SizedBox(height: 8),
                  const ComingSoonBadge(),
                ],
              ],
            ),
          ),
          if (onAddPet != null)
            const Icon(Icons.add_circle, color: AppColors.primary, size: 32),
        ],
      ),
    );
  }
}

class _PetError extends StatelessWidget {
  const _PetError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.cloud_off, color: AppColors.textMuted),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('No pudimos cargar tus mascotas. Verifica tu conexión.'),
        ),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    );
  }
}

class _PetLoading extends StatelessWidget {
  const _PetLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 64,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
