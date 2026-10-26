import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/appointments_providers.dart';
import '../../../../core/data/appointments_repository.dart';
import '../../../../core/domain/appointment.dart';
import '../../../../core/domain/clinic.dart';
import '../../../../core/format/time_format.dart';
import '../../../../core/theme/app_theme.dart';
import 'appointment_status_chip.dart';
import 'booking_format.dart';
import 'booking_logic.dart';
import 'booking_providers.dart';

/// Detalle de una cita del dueño (`/reservas/:id`, también desde las
/// notificaciones): datos, estado, motivo, "Cómo llegar", "Llamar a la
/// clínica" y "Cancelar cita" hasta 2 horas antes.
class AppointmentDetailPage extends ConsumerStatefulWidget {
  const AppointmentDetailPage({super.key, required this.appointmentId});

  final String appointmentId;

  /// "Cómo llegar": app de mapas del teléfono; si no hay, OpenStreetMap.
  static List<Uri> directionsUris(Clinic c) => [
        Uri.parse('geo:${c.lat},${c.lng}?q=${c.lat},${c.lng}(${Uri.encodeComponent(c.nombre)})'),
        Uri.https('www.openstreetmap.org', '/directions', {'route': ';${c.lat},${c.lng}'}),
      ];

  static Uri callUri(String phone) => Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));

  @override
  ConsumerState<AppointmentDetailPage> createState() => _AppointmentDetailPageState();
}

class _AppointmentDetailPageState extends ConsumerState<AppointmentDetailPage> {
  bool _cancelling = false;

  Future<void> _open(List<Uri> uris, String error) async {
    final messenger = ScaffoldMessenger.of(context);
    final opener = ref.read(bookingUrlOpenerProvider);
    for (final uri in uris) {
      try {
        if (await opener(uri)) return;
      } catch (_) {}
    }
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _cancel(Appointment a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar la cita?'),
        content: Text(
          'Se liberará el horario de ${a.petNombre} y avisaremos a ${a.clinicNombre}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar cita'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _cancelling = true);
    try {
      await ref.read(appointmentsRepositoryProvider).cancel(a.id);
      messenger.showSnackBar(const SnackBar(content: Text('Cita cancelada')));
    } on AppointmentFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appointment = ref.watch(appointmentProvider(widget.appointmentId));
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de la cita')),
      body: switch (appointment) {
        AsyncData(value: final Appointment a) => _body(a),
        AsyncData() => const Center(child: Text('No encontramos esta cita.')),
        AsyncError() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No pudimos cargar la cita. Verifica tu conexión.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(appointmentProvider(widget.appointmentId)),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(Appointment a) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    final now = ref.watch(bookingClockProvider)();
    final clinic = ref.watch(bookingClinicProvider(a.clinicId)).value;
    final canCancelState = canTransition(a.estado, AppointmentStatus.cancelada);
    final blockedReason = BookingLogic.cancelBlockedReason(a, now);
    final reason = switch (a.estado) {
      AppointmentStatus.rechazada => a.motivoRechazo,
      AppointmentStatus.cancelada => a.motivoCancelacion,
      _ => null,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                a.serviceNombre,
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            AppointmentStatusChip(status: a.estado),
          ],
        ),
        const SizedBox(height: 12),
        _Line(icon: Icons.pets, text: a.petNombre),
        _Line(icon: Icons.local_hospital_outlined, text: a.clinicNombre),
        if (clinic != null && clinic.direccion.isNotEmpty)
          _Line(icon: Icons.place_outlined, text: clinic.direccion),
        _Line(icon: Icons.event_outlined, text: formatAppointmentDay(a.inicio)),
        _Line(icon: Icons.schedule, text: TimeFormat.hour(a.hora)),
        _Line(icon: Icons.payments_outlined, text: formatCop(a.precioAcordado)),
        if (a.comentario.isNotEmpty) _Line(icon: Icons.notes_outlined, text: a.comentario),
        if (a.cancelledByClinic)
          const _Notice(text: 'La clínica canceló esta cita. Puedes agendar otro horario.'),
        if (reason != null && reason.isNotEmpty) _Notice(text: 'Motivo: $reason'),
        if (a.estado == AppointmentStatus.pendiente)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Esperando la respuesta de la clínica.', style: muted),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: clinic == null
                    ? null
                    : () => _open(
                          AppointmentDetailPage.directionsUris(clinic),
                          'No se pudo abrir el mapa',
                        ),
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Cómo llegar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: clinic == null || clinic.telefono.isEmpty
                    ? null
                    : () => _open(
                          [AppointmentDetailPage.callUri(clinic.telefono)],
                          'No se pudo abrir el teléfono',
                        ),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Llamar a la clínica'),
              ),
            ),
          ],
        ),
        if (canCancelState) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.sos,
              side: BorderSide(
                color: blockedReason == null ? AppColors.sos : AppColors.border,
              ),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: blockedReason != null || _cancelling ? null : () => _cancel(a),
            child: _cancelling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cancelar cita'),
          ),
          if (blockedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(blockedReason, style: muted, textAlign: TextAlign.center),
            ),
        ],
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.sosContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.sosBorder),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.sos)),
    );
  }
}
