import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/appointments_providers.dart';
import '../../../../core/data/appointments_repository.dart';
import '../../../../core/domain/appointment.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/kernel/plugin_registry.dart';
import '../../../../core/theme/app_theme.dart';
import '../dueno/appointment_status_chip.dart';
import '../dueno/booking_format.dart';
import 'appointment_pet_avatar.dart';
import 'clinic_requests_providers.dart';
import 'clinic_routes.dart';
import 'reason_dialog.dart';

/// Detalle de una cita para la clínica (RF-14): datos completos, acceso al
/// historial de la mascota y las acciones según el estado. Todo cambio de
/// estado va por AppointmentsRepository (Edge Function `citas`).
class ClinicAppointmentDetailPage extends ConsumerStatefulWidget {
  const ClinicAppointmentDetailPage({super.key, required this.appointmentId});

  final String appointmentId;

  static const alreadyAnswered = 'Otra persona ya respondió esta solicitud.';
  static const cancelWarning = 'El dueño será notificado de la cancelación.';

  @override
  ConsumerState<ClinicAppointmentDetailPage> createState() =>
      _ClinicAppointmentDetailPageState();
}

class _ClinicAppointmentDetailPageState extends ConsumerState<ClinicAppointmentDetailPage> {
  bool _busy = false;

  /// Estado con el que se abrió la pantalla y si la acción fue de aquí: si
  /// una solicitud deja de estar pendiente sin que la respondiéramos, otra
  /// persona la respondió.
  AppointmentStatus? _openedAs;
  bool _actedHere = false;

  AppointmentsRepository get _repo => ref.read(appointmentsRepositoryProvider);

  void _snack(String text, {bool success = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: success ? AppColors.success : null,
        content: Text(text, style: success ? const TextStyle(color: AppColors.onPrimary) : null),
      ));
  }

  /// Corre una acción del repositorio con el estado de carga y los errores.
  Future<bool> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _actedHere = true;
    });
    try {
      await action();
      if (mounted) _snack(success, success: true);
      return true;
    } on AppointmentFailure catch (e) {
      if (mounted) _snack(e.message);
      return false;
    } catch (_) {
      if (mounted) _snack('No se pudo completar la acción. Intenta de nuevo.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Appointment a) =>
      _run(() => _repo.approve(a.id), 'Cita aprobada. Le avisamos al dueño.');

  Future<void> _reject(Appointment a) async {
    final motivo = await showReasonDialog(
      context,
      title: 'Rechazar solicitud',
      confirmLabel: 'Rechazar',
      warning: 'El dueño verá el motivo del rechazo.',
    );
    if (motivo == null || !mounted) return;
    await _run(() => _repo.reject(a.id, motivo), 'Solicitud rechazada.');
  }

  Future<void> _cancel(Appointment a) async {
    final motivo = await showReasonDialog(
      context,
      title: 'Cancelar cita',
      confirmLabel: 'Cancelar cita',
      warning: ClinicAppointmentDetailPage.cancelWarning,
    );
    if (motivo == null || !mounted) return;
    await _run(
      () => _repo.cancel(a.id, motivo: motivo, byClinic: true),
      'Cita cancelada. Le avisamos al dueño.',
    );
  }

  Future<void> _complete(Appointment a) async {
    final ok = await _run(() => _repo.complete(a.id), 'Cita marcada como atendida.');
    if (!ok || !mounted) return;
    final register = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cita atendida'),
        content: Text('¿Quieres registrar ahora la consulta de ${a.petNombre}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Más tarde')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Registrar consulta'),
          ),
        ],
      ),
    );
    if (register == true && mounted) _openRecordForm(a);
  }

  void _openRecordForm(Appointment a) =>
      context.push(ClinicAppointmentRoutes.newRecord(a.petId, a.id));

  @override
  Widget build(BuildContext context) {
    final appointment = ref.watch(appointmentProvider(widget.appointmentId));
    Widget scaffold(Widget body) =>
        Scaffold(appBar: AppBar(title: const Text('Detalle de la cita')), body: body);

    return switch (appointment) {
      AsyncValue(value: final Appointment a) => scaffold(_body(a)),
      AsyncData() => scaffold(const _Centered(text: 'Esta cita ya no existe.')),
      AsyncError() => scaffold(_Centered(
          text: 'No pudimos cargar la cita. Verifica tu conexión.',
          onRetry: () => ref.invalidate(appointmentProvider(widget.appointmentId)),
        )),
      _ => scaffold(const Center(child: CircularProgressIndicator())),
    };
  }

  Widget _body(Appointment a) {
    _openedAs ??= a.estado;
    final answeredElsewhere = _openedAs == AppointmentStatus.pendiente &&
        a.estado != AppointmentStatus.pendiente &&
        !_actedHere;
    final now = ref.read(appointmentClockProvider)();
    final textTheme = Theme.of(context).textTheme;
    final pet = ref.watch(clinicPetProvider(a.petId)).value;
    final canSeeHistory =
        ref.read(pluginRegistryProvider).hasRoute(ClinicAppointmentRoutes.patient(a.petId));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (answeredElsewhere)
          _Banner(
            text: '${ClinicAppointmentDetailPage.alreadyAnswered} '
                'Ahora está: ${a.estado.label.toLowerCase()}.',
          ),
        _PetHeader(appointment: a, pet: pet),
        if (pet != null) _Allergies(pet: pet),
        if (canSeeHistory)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push(ClinicAppointmentRoutes.patient(a.petId)),
              icon: const Icon(Icons.medical_information_outlined),
              label: const Text('Ver historial médico'),
            ),
          ),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(a.serviceNombre,
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            AppointmentStatusChip(status: a.estado),
          ],
        ),
        const SizedBox(height: 8),
        _Info(icon: Icons.event_outlined, text: formatAppointmentDay(a.inicio)),
        _Info(
          icon: Icons.schedule,
          text: [
            formatAppointmentShort(a.inicio, a.hora).split(' · ').last,
            if (a.duracionMin != null) '${a.duracionMin} min',
          ].join(' · '),
        ),
        _Info(icon: Icons.payments_outlined, text: formatCop(a.precioAcordado)),
        if (a.ownerNombre.isNotEmpty) _Info(icon: Icons.person_outline, text: a.ownerNombre),
        if (a.comentario.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Comentario del dueño',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          Text('“${a.comentario.trim()}”', style: const TextStyle(fontStyle: FontStyle.italic)),
        ],
        if (a.motivoRechazo case final motivo?) _Reason(title: 'Motivo del rechazo', text: motivo),
        if (a.motivoCancelacion case final motivo?)
          _Reason(
            title: a.canceladoPor == CancelledBy.dueno
                ? 'Cancelada por el dueño'
                : 'Motivo de la cancelación',
            text: motivo,
          ),
        const SizedBox(height: 24),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else
          ..._actions(a, now),
      ],
    );
  }

  List<Widget> _actions(Appointment a, DateTime now) => switch (a.estado) {
        AppointmentStatus.pendiente => [
            FilledButton.icon(
              onPressed: () => _approve(a),
              icon: const Icon(Icons.check),
              label: const Text('Aprobar'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _reject(a),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.sos,
                side: const BorderSide(color: AppColors.sos),
              ),
              icon: const Icon(Icons.close),
              label: const Text('Rechazar'),
            ),
          ],
        AppointmentStatus.confirmada => [
            if (a.canComplete(now))
              FilledButton.icon(
                onPressed: () => _complete(a),
                icon: const Icon(Icons.task_alt),
                label: const Text('Marcar como atendida'),
              )
            else
              Text(
                'Podrás marcarla como atendida a partir de la hora de la cita.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _cancel(a),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.sos,
                side: const BorderSide(color: AppColors.sos),
              ),
              icon: const Icon(Icons.event_busy),
              label: const Text('Cancelar cita'),
            ),
          ],
        AppointmentStatus.completada => [
            FilledButton.icon(
              onPressed: () => _openRecordForm(a),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Registrar consulta'),
            ),
          ],
        _ => const [],
      };
}

class _PetHeader extends StatelessWidget {
  const _PetHeader({required this.appointment, required this.pet});

  final Appointment appointment;
  final Pet? pet;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = pet;
    return Row(
      children: [
        AppointmentPetAvatar(photoPath: p?.fotoPath, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(appointment.petNombre,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              if (p != null)
                Text(p.summary(DateTime.now()),
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Alergias y condiciones resaltadas en rojo, como en el perfil del paciente.
class _Allergies extends StatelessWidget {
  const _Allergies({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final items = [...pet.alergias, ...pet.condiciones];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in items)
            Chip(
              avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.sos),
              label: Text(item, style: const TextStyle(color: AppColors.sos)),
              backgroundColor: AppColors.sosContainer,
              side: const BorderSide(color: AppColors.sosBorder),
              visualDensity: VisualDensity.compact,
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _Reason extends StatelessWidget {
  const _Reason({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            Text(text),
          ],
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.slotBlockedContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.slotBlocked),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
              ],
            ],
          ),
        ),
      );
}
