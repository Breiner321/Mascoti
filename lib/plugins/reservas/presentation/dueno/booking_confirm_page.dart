import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/appointments_providers.dart';
import '../../../../core/data/appointments_repository.dart';
import '../../../../core/domain/clinic.dart';
import '../../../../core/domain/clinic_service.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/domain/slot.dart';
import '../../../../core/format/time_format.dart';
import '../../../../core/theme/app_theme.dart';
import 'booking_format.dart';

/// Resultado de la confirmación: la cita creada, o el horario ya lo tomó
/// otra persona (hay que refrescar el calendario).
typedef BookingOutcome = ({String? appointmentId, bool slotTaken});

/// Resumen antes de enviar la solicitud (RF-14 pasos 4-6).
class BookingConfirmPage extends ConsumerStatefulWidget {
  const BookingConfirmPage({
    super.key,
    required this.clinic,
    required this.service,
    required this.pet,
    required this.slot,
    required this.comentario,
  });

  final Clinic clinic;
  final ClinicService service;
  final Pet pet;
  final Slot slot;
  final String comentario;

  @override
  ConsumerState<BookingConfirmPage> createState() => _BookingConfirmPageState();
}

class _BookingConfirmPageState extends ConsumerState<BookingConfirmPage> {
  bool _sending = false;

  Future<void> _submit() async {
    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ref.read(appointmentsRepositoryProvider).request(
            clinicId: widget.clinic.id,
            serviceId: widget.service.id,
            petId: widget.pet.id,
            slotId: widget.slot.id,
            comentario: widget.comentario,
          );
      navigator.pop<BookingOutcome>((appointmentId: id, slotTaken: false));
    } on AppointmentFailure catch (e) {
      if (e.slotTaken) {
        navigator.pop<BookingOutcome>((appointmentId: null, slotTaken: true));
        return;
      }
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        action: e.canRetry ? SnackBarAction(label: 'Reintentar', onPressed: _submit) : null,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final slot = widget.slot;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar cita')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row(icon: Icons.local_hospital_outlined, label: 'Clínica', value: widget.clinic.nombre),
                _Row(
                  icon: Icons.medical_services_outlined,
                  label: 'Servicio',
                  value: '${widget.service.nombre} · ${formatCop(slot.precio ?? widget.service.precio)}',
                ),
                _Row(icon: Icons.pets, label: 'Mascota', value: widget.pet.nombre),
                _Row(
                  icon: Icons.event_outlined,
                  label: 'Fecha',
                  value: formatAppointmentDay(slot.inicio),
                ),
                _Row(icon: Icons.schedule, label: 'Hora', value: TimeFormat.hour(slot.hora)),
                if (widget.comentario.trim().isNotEmpty)
                  _Row(
                    icon: Icons.notes_outlined,
                    label: 'Comentario',
                    value: widget.comentario.trim(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Al solicitar la cita, la clínica podrá ver el historial médico de ${widget.pet.nombre}',
                    style: textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: _sending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Solicitar Cita'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                Text(value, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
