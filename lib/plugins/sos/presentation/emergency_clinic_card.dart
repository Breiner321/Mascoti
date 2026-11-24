import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/emergency_ranking.dart';

/// Tarjeta de una veterinaria en el SOS (RF-10): nombre grande, distancia,
/// "Llamar" (el botón más grande) y "Cómo llegar". Las aliadas llevan la
/// huella y el texto "Aliado Mascoti" (forma y texto, no solo color). Sin
/// teléfono, solo "Cómo llegar".
class EmergencyClinicCard extends StatelessWidget {
  const EmergencyClinicCard({
    super.key,
    required this.vet,
    required this.onCall,
    required this.onDirections,
  });

  final EmergencyVet vet;

  /// Se llama con el teléfono de [vet]; no se usa si no tiene.
  final VoidCallback onCall;
  final VoidCallback onDirections;

  static const allyLabel = 'Aliado Mascoti';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final clinic = vet.clinic;
    final distance = vet.distanceKm;
    final hasPhone = vet.telefono?.trim().isNotEmpty ?? false;

    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: vet.priority == 0 ? AppColors.sos : AppColors.border,
          width: vet.priority == 0 ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _VetIcon(ally: clinic.aliada),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vet.nombre,
                        style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        distance == null ? 'Distancia desconocida' : 'A ${distanceText(distance)}',
                        style: text.titleMedium?.copyWith(color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (clinic.aliada) const _Tag(icon: Icons.pets, label: allyLabel),
                if (clinic.emergencias)
                  const _Tag(icon: Icons.local_hospital_outlined, label: 'Atiende emergencias'),
                if (clinic.abierto24h) const _Tag(icon: Icons.schedule, label: '24 horas'),
                if (vet.favorite) const _Tag(icon: Icons.history, label: 'Ya fuiste'),
              ],
            ),
            const SizedBox(height: 16),
            if (hasPhone) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sos,
                  foregroundColor: AppColors.onPrimary,
                  minimumSize: const Size.fromHeight(64),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  textStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: onCall,
                icon: const Icon(Icons.phone, size: 28),
                label: Text('Llamar', semanticsLabel: 'Llamar a ${vet.nombre}'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                minimumSize: const Size.fromHeight(56),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                side: BorderSide(color: AppColors.outline, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: onDirections,
              icon: const Icon(Icons.directions, size: 24),
              label: Text('Cómo llegar', semanticsLabel: 'Cómo llegar a ${vet.nombre}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aliada: círculo con huella. Otra veterinaria: cruz médica (Cambio 4).
class _VetIcon extends StatelessWidget {
  const _VetIcon({required this.ally});

  final bool ally;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: ally ? AppColors.primary : AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: ally ? AppColors.primary : AppColors.outline, width: 2),
        ),
        child: Icon(
          ally ? Icons.pets : Icons.medical_services_outlined,
          size: 24,
          color: ally ? AppColors.onPrimary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
