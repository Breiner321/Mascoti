import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/pet.dart';
import 'coming_soon_badge.dart';

/// Tarjeta "Mi mascota" del home: cargando, vacío, error y datos.
class PetSummaryCard extends StatelessWidget {
  const PetSummaryCard({
    super.key,
    required this.pets,
    required this.onRetry,
    required this.onAddPet,
    required this.onOpenList,
  });

  final AsyncValue<List<Pet>> pets;
  final VoidCallback onRetry;

  /// null = el registro de mascotas aún no existe (semana 2).
  final VoidCallback? onAddPet;
  final VoidCallback? onOpenList;

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
        AsyncData(:final value) => _PetInfo(pet: value.first, onOpenList: onOpenList),
        AsyncError() => _PetError(onRetry: onRetry),
        _ => const _PetLoading(),
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryContainer,
        border: Border.all(color: AppColors.primary, width: 2),
        image: url == null
            ? null
            : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: url == null
          ? const Icon(Icons.pets, color: AppColors.primary, size: 30)
          : null,
    );
  }
}

class _PetInfo extends StatelessWidget {
  const _PetInfo({required this.pet, required this.onOpenList});

  final Pet pet;
  final VoidCallback? onOpenList;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summary = pet.summary(DateTime.now());
    return Row(
      children: [
        _Avatar(photoUrl: pet.fotoUrl),
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
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: onOpenList == null ? 'Mis mascotas · Próximamente' : 'Mis mascotas',
          onPressed: onOpenList,
          icon: const Icon(Icons.menu),
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
          const _Avatar(),
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
