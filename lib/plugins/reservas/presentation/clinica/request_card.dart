import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/appointment.dart';
import '../../../../core/theme/app_theme.dart';
import '../dueno/booking_format.dart';
import 'appointment_pet_avatar.dart';
import 'clinic_requests_providers.dart';

/// Solicitud pendiente en la bandeja de la clínica (RF-14): mascota (foto,
/// nombre, especie), dueño, servicio, fecha y hora, y comentario del dueño.
class RequestCard extends ConsumerWidget {
  const RequestCard({super.key, required this.appointment, required this.onTap});

  final Appointment appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = appointment;
    final pet = ref.watch(clinicPetProvider(a.petId)).value;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: AppColors.textMuted);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppointmentPetAvatar(photoPath: pet?.fotoPath),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.petNombre,
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          [
                            if (pet != null) pet.especie.label,
                            if (a.ownerNombre.isNotEmpty) 'Dueño: ${a.ownerNombre}',
                          ].join(' · '),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
              const SizedBox(height: 12),
              _Line(icon: Icons.medical_services_outlined, text: a.serviceNombre),
              _Line(
                icon: Icons.event_outlined,
                text: formatAppointmentShort(a.inicio, a.hora),
              ),
              if (a.comentario.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '“${a.comentario.trim()}”',
                    style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
