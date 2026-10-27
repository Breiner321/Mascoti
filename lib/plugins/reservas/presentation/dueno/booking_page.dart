import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/appointments_repository.dart';
import '../../../../core/domain/appointment.dart';
import '../../../../core/domain/clinic.dart';
import '../../../../core/domain/clinic_service.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/domain/slot.dart';
import '../../../../core/format/bogota_time.dart';
import '../../../../core/format/time_format.dart';
import '../../../../core/kernel/plugin_registry.dart';
import '../../../../core/theme/app_theme.dart';
import 'booking_calendar.dart';
import 'booking_confirm_page.dart';
import 'booking_format.dart';
import 'booking_logic.dart';
import 'booking_providers.dart';
import 'clinic_picker_view.dart';
import 'owner_routes.dart';

/// "Agendar cita" (mockup VISTA CLIENTE, cuarta pantalla; RF-14 pasos 1-3).
/// Sin [clinicId] primero se elige la clínica. [categoria] preselecciona el
/// primer servicio de esa categoría (accesos "Servicios" del home).
class BookingPage extends ConsumerStatefulWidget {
  const BookingPage({super.key, this.clinicId, this.categoria});

  final String? clinicId;
  final String? categoria;

  @override
  ConsumerState<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends ConsumerState<BookingPage> {
  late String? _clinicId = widget.clinicId;
  String? _serviceId;
  String? _petId;
  String? _fecha;
  String? _hora;
  DateTime? _focusedDay;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _selectService(String id) => setState(() {
        _serviceId = id;
        _fecha = null;
        _hora = null;
      });

  Future<void> _continue({
    required Clinic clinic,
    required ClinicService service,
    required Pet pet,
    required Slot slot,
    required ({String clinicId, int year, int month}) monthKey,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await Navigator.of(context).push<BookingOutcome>(
      MaterialPageRoute(
        builder: (_) => BookingConfirmPage(
          clinic: clinic,
          service: service,
          pet: pet,
          slot: slot,
          comentario: _comment.text,
        ),
      ),
    );
    if (!mounted || outcome == null) return;
    if (outcome.slotTaken) {
      // RF-14, flujo alterno: otro usuario tomó el horario.
      setState(() => _hora = null);
      ref.invalidate(monthSlotsProvider(monthKey));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AppointmentFailure.slotUnavailable.message)));
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Solicitud enviada. La clínica te confirmará la cita.')),
    );
    context.pushReplacement(OwnerBookingRoutes.detail(outcome.appointmentId!));
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = _clinicId;
    return Scaffold(
      appBar: AppBar(title: const Text('Agendar cita')),
      body: clinicId == null
          ? ClinicPickerView(onPick: (id) => setState(() => _clinicId = id))
          : _buildForClinic(clinicId),
    );
  }

  Widget _buildForClinic(String clinicId) {
    final clinic = ref.watch(bookingClinicProvider(clinicId));
    final services = ref.watch(bookingServicesProvider(clinicId));
    final pets = ref.watch(ownerPetsProvider);

    if (clinic.hasError || services.hasError || pets.hasError) {
      return _Message(
        text: 'No pudimos cargar la información. Verifica tu conexión.',
        action: 'Reintentar',
        onAction: () {
          ref.invalidate(bookingClinicProvider(clinicId));
          ref.invalidate(bookingServicesProvider(clinicId));
          ref.invalidate(ownerPetsProvider);
        },
      );
    }
    if (!clinic.hasValue || !services.hasValue || !pets.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final c = clinic.value;
    if (c == null) return const _Message(text: 'No encontramos esta clínica.');
    if (!c.isActive) {
      return const _Message(text: 'Esta clínica no está recibiendo citas en este momento.');
    }
    final myPets = pets.value!;
    if (myPets.isEmpty) {
      final canRegister = ref.watch(pluginRegistryProvider).hasRoute(OwnerBookingRoutes.newPet);
      return _Message(
        text: 'Para agendar una cita primero registra a tu mascota.',
        action: canRegister ? 'Registrar mascota' : null,
        onAction: () => context.push(OwnerBookingRoutes.newPet),
      );
    }
    final list = services.value!;
    if (list.isEmpty) {
      return const _Message(text: 'Esta clínica aún no tiene servicios para agendar.');
    }
    return _form(c, list, myPets);
  }

  Widget _form(Clinic clinic, List<ClinicService> services, List<Pet> pets) {
    final textTheme = Theme.of(context).textTheme;
    final now = ref.watch(bookingClockProvider)();
    final today = BogotaTime.wallClock(now);
    final firstDay = DateTime.utc(today.year, today.month, 1);
    final lastDay = DateTime.utc(today.year + 1, today.month, today.day);
    final focused = _focusedDay ?? DateTime.utc(today.year, today.month, today.day);

    final service = services.where((s) => s.id == _serviceId).firstOrNull ??
        services.where((s) => s.categoria.value == widget.categoria).firstOrNull ??
        services.first;
    final pet = pets.where((p) => p.id == _petId).firstOrNull ?? pets.first;

    // Cambio 2: los días y horas salen del horario de la clínica, sus
    // excepciones y las franjas ya apartadas, todo en tiempo real.
    final monthKey = (clinicId: clinic.id, year: focused.year, month: focused.month);
    final slots = ref.watch(monthSlotsProvider(monthKey));
    final exceptionsKey = (clinicId: clinic.id, desde: BogotaTime.dateKey(now));
    final exceptions = ref.watch(clinicExceptionsProvider(exceptionsKey));
    final monthSlots = slots.value ?? const <Slot>[];
    final monthExceptions = exceptions.value ?? const [];
    final days = BookingLogic.availableDays(
      clinic: clinic,
      durationMin: service.duracionMin,
      year: focused.year,
      month: focused.month,
      slots: monthSlots,
      now: now,
      exceptions: monthExceptions,
    );
    // El día elegido deja de servir si se quedó sin horas (otro las tomó).
    final fecha = days.contains(_fecha) ? _fecha : null;
    final hours = fecha == null
        ? const <String>[]
        : BookingLogic.hoursOf(
            clinic: clinic,
            durationMin: service.duracionMin,
            fecha: fecha,
            slots: monthSlots,
            now: now,
            exceptions: monthExceptions,
          );
    // Igual con la hora: si otro usuario la tomó, desaparece y se deselecciona.
    final hora = hours.contains(_hora) ? _hora : null;
    final slot = fecha == null || hora == null
        ? null
        : Slot.at(fecha: fecha, hora: hora, estado: SlotStatus.disponible);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            text,
            style: textTheme.labelMedium
                ?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(clinic.nombre, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        label('SERVICIO'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in services)
              ChoiceChip(
                label: Text('${s.nombre} · ${formatCop(s.precio)}'),
                selected: s.id == service.id,
                onSelected: (_) => _selectService(s.id),
              ),
          ],
        ),
        if (pets.length > 1) ...[
          label('MASCOTA'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in pets)
                ChoiceChip(
                  avatar: const Icon(Icons.pets, size: 18),
                  label: Text(p.nombre),
                  selected: p.id == pet.id,
                  onSelected: (_) => setState(() => _petId = p.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        BookingCalendar(
          firstDay: firstDay,
          lastDay: lastDay,
          focusedDay: focused,
          selectedFecha: fecha,
          availableDays: days,
          onDaySelected: (f) => setState(() {
            _fecha = f;
            _hora = null;
            final d = DateTime.parse(f);
            _focusedDay = DateTime.utc(d.year, d.month, d.day);
          }),
          onPageChanged: (day) => setState(() {
            _focusedDay = day;
            _fecha = null;
            _hora = null;
          }),
        ),
        label('HORARIO'),
        switch (slots) {
          _ when slots.hasError || exceptions.hasError => _Inline(
              text: 'No pudimos cargar los horarios.',
              action: 'Reintentar',
              onAction: () {
                ref.invalidate(monthSlotsProvider(monthKey));
                ref.invalidate(clinicExceptionsProvider(exceptionsKey));
              },
            ),
          _ when !slots.hasValue || !exceptions.hasValue =>
            const Center(child: CircularProgressIndicator()),
          _ when days.isEmpty =>
            const _Inline(text: 'No hay horarios disponibles este mes para este servicio.'),
          _ when fecha == null => const _Inline(text: 'Elige un día resaltado en el calendario.'),
          _ => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in hours)
                  ChoiceChip(
                    label: Text(TimeFormat.hour(h)),
                    selected: h == hora,
                    onSelected: (_) => setState(() => _hora = h),
                  ),
              ],
            ),
        },
        label('COMENTARIO (OPCIONAL)'),
        TextField(
          controller: _comment,
          maxLength: AppointmentLimits.maxComentario,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'Ej. Vómito desde ayer'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: slot == null
              ? null
              : () => _continue(
                    clinic: clinic,
                    service: service,
                    pet: pet,
                    slot: slot,
                    monthKey: monthKey,
                  ),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Inline extends StatelessWidget {
  const _Inline({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}
