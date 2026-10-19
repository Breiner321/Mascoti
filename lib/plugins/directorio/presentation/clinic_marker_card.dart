import 'package:flutter/material.dart';

import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/clinic_schedule.dart';
import '../domain/directory_filters.dart';

/// Tarjeta al tocar un marcador (RF-09 paso 7): nombre, distancia, especies
/// atendidas, teléfono, "Ver perfil" y "Agendar".
class ClinicMarkerCard extends StatelessWidget {
  const ClinicMarkerCard({
    super.key,
    required this.nearby,
    required this.onViewProfile,
    required this.onSchedule,
  });

  final NearbyClinic nearby;
  final VoidCallback onViewProfile;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final clinic = nearby.clinic;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    final rating = clinic.calificacion;
    final open = openLabel(clinic.horarioBase, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(clinic.nombre,
              style:
                  textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Info(
                  icon: Icons.near_me_outlined,
                  text: distanceLabel(nearby.distanceKm)),
              if (rating != null)
                _Info(
                    icon: Icons.star_rounded, text: rating.toStringAsFixed(1)),
              if (open != null)
                _Info(
                  icon: Icons.schedule,
                  text:
                      '$open · ${clinic.horarioBase!.apertura}–${clinic.horarioBase!.cierre}',
                ),
              if (clinic.atencionEmergencias)
                const _Info(
                    icon: Icons.emergency_outlined, text: 'Emergencias'),
            ],
          ),
          const SizedBox(height: 12),
          Text('Especies atendidas', style: muted),
          const SizedBox(height: 4),
          if (clinic.tiposAnimales.isEmpty)
            const Text('Sin especies registradas')
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in clinic.tiposAnimales)
                  Chip(
                      label: Text(t.label),
                      visualDensity: VisualDensity.compact),
              ],
            ),
          if (clinic.telefono.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Info(icon: Icons.phone_outlined, text: clinic.telefono),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: onViewProfile, child: const Text('Ver perfil')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                    onPressed: onSchedule, child: const Text('Agendar')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}
