import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/appointments_providers.dart';
import '../../../../core/domain/appointment.dart';
import '../../../../core/theme/app_theme.dart';
import 'appointment_status_chip.dart';
import 'booking_format.dart';
import 'booking_logic.dart';
import 'booking_providers.dart';
import 'owner_routes.dart';

/// Pestaña "Citas" del dueño: Próximas e Historial, en tiempo real (RF-14
/// paso 10).
class MyAppointmentsPage extends ConsumerWidget {
  const MyAppointmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider)?.uid;
    if (uid == null) return const SizedBox.shrink();
    final appointments = ref.watch(ownerAppointmentsProvider(uid));
    final now = ref.watch(bookingClockProvider)();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(OwnerBookingRoutes.newAppointment),
          icon: const Icon(Icons.add),
          label: const Text('Agendar cita'),
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mis citas',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const TabBar(tabs: [Tab(text: 'Próximas'), Tab(text: 'Historial')]),
            Expanded(
              child: switch (appointments) {
                AsyncData(:final value) => () {
                    final split = BookingLogic.split(value, now);
                    return TabBarView(
                      children: [
                        _AppointmentList(
                          items: split.upcoming,
                          empty: 'No tienes citas próximas.',
                        ),
                        _AppointmentList(
                          items: split.history,
                          empty: 'Aún no tienes citas anteriores.',
                        ),
                      ],
                    );
                  }(),
                AsyncError() => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No pudimos cargar tus citas. Verifica tu conexión.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => ref.invalidate(ownerAppointmentsProvider(uid)),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({required this.items, required this.empty});

  final List<Appointment> items;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(empty, style: const TextStyle(color: AppColors.textMuted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _AppointmentTile(appointment: items[i]),
    );
  }
}

/// Tarjeta de una cita en "Mis citas".
class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(OwnerBookingRoutes.detail(a.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${a.serviceNombre} · ${a.petNombre}',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  AppointmentStatusChip(status: a.estado),
                ],
              ),
              const SizedBox(height: 4),
              Text(a.clinicNombre, style: muted),
              const SizedBox(height: 4),
              Text(formatAppointmentShort(a.inicio, a.hora), style: textTheme.bodyMedium),
              if (a.estado == AppointmentStatus.rechazada && (a.motivoRechazo ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Motivo: ${a.motivoRechazo}',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.sos)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
