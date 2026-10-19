import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/clinic.dart';
import '../../../core/domain/clinic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/clinic_schedule.dart';
import 'directory_providers.dart';
import 'schedule_action.dart';

final _thousands = NumberFormat('#,##0', 'es_CO');

/// 45000 → "$ 45.000".
String _cop(double value) => '\$ ${_thousands.format(value.round())}';

/// Perfil público de una clínica (RF-09): datos, especies, servicios activos
/// con precio, "Llamar", "Cómo llegar" y "Agendar".
class ClinicPublicProfilePage extends ConsumerWidget {
  const ClinicPublicProfilePage({super.key, required this.clinicId});

  final String clinicId;

  /// "Cómo llegar": abre la app de mapas del teléfono (Google Maps, OsmAnd…)
  /// en la clínica. Sin app de mapas, la ruta en OpenStreetMap
  /// ([osmDirectionsUri]).
  static Uri directionsUri(Clinic clinic) =>
      Uri.parse('geo:${clinic.lat},${clinic.lng}?q=${clinic.lat},${clinic.lng}'
          '(${Uri.encodeComponent(clinic.nombre)})');

  static Uri osmDirectionsUri(Clinic clinic) => Uri.https(
      'www.openstreetmap.org',
      '/directions',
      {'route': ';${clinic.lat},${clinic.lng}'});

  static Uri callUri(String phone) =>
      Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));

  /// Abre el primer enlace que el teléfono pueda abrir; si ninguno, [error].
  Future<void> _open(
      BuildContext context, WidgetRef ref, List<Uri> uris, String error) async {
    final messenger = ScaffoldMessenger.of(context);
    final opener = ref.read(directoryUrlOpenerProvider);
    for (final uri in uris) {
      try {
        if (await opener(uri)) return;
      } catch (_) {}
    }
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(clinicProfileProvider(clinicId));
    return Scaffold(
      appBar: AppBar(title: Text(clinic.value?.nombre ?? 'Clínica')),
      body: switch (clinic) {
        AsyncValue(value: final Clinic c) => _Profile(
            clinic: c,
            onCall: () => _open(context, ref, [callUri(c.telefono)],
                'No se pudo abrir el teléfono'),
            onDirections: () => _open(
                context,
                ref,
                [directionsUri(c), osmDirectionsUri(c)],
                'No se pudo abrir el mapa'),
            onSchedule: () => openSchedule(context, ref, c.id),
          ),
        AsyncData() =>
          const Center(child: Text('No encontramos esta clínica.')),
        AsyncError() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'No pudimos cargar la clínica. Verifica tu conexión.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(clinicProfileProvider(clinicId)),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({
    required this.clinic,
    required this.onCall,
    required this.onDirections,
    required this.onSchedule,
  });

  final Clinic clinic;
  final VoidCallback onCall;
  final VoidCallback onDirections;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    final hours = clinic.horarioBase;
    final open = openLabel(hours, DateTime.now());
    final services = ref.watch(clinicActiveServicesProvider(clinic.id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(clinic.nombre,
            style:
                textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _Line(icon: Icons.place_outlined, text: clinic.direccion),
        if (clinic.telefono.isNotEmpty)
          _Line(icon: Icons.phone_outlined, text: clinic.telefono),
        if (hours != null)
          _Line(
            icon: Icons.schedule,
            text:
                '${open == null ? '' : '$open · '}${hours.apertura}–${hours.cierre}',
          ),
        if (clinic.atencionEmergencias)
          const _Line(
              icon: Icons.emergency_outlined, text: 'Atiende emergencias'),
        if (clinic.calificacion case final rating?)
          _Line(icon: Icons.star_rounded, text: rating.toStringAsFixed(1)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: clinic.telefono.isEmpty ? null : onCall,
                icon: const Icon(Icons.call_outlined),
                label: const Text('Llamar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDirections,
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Cómo llegar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: onSchedule, child: const Text('Agendar')),
        const SizedBox(height: 24),
        Text('Especies atendidas', style: muted),
        const SizedBox(height: 6),
        if (clinic.tiposAnimales.isEmpty)
          const Text('Sin especies registradas')
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in clinic.tiposAnimales) Chip(label: Text(t.label))
            ],
          ),
        const SizedBox(height: 24),
        Text('Servicios', style: muted),
        const SizedBox(height: 6),
        switch (services) {
          AsyncData(:final value) when value.isEmpty =>
            const Text('Esta clínica aún no publica sus servicios.'),
          AsyncData(:final value) => Column(
              children: [for (final s in value) _ServiceTile(service: s)],
            ),
          AsyncError() => Row(
              children: [
                const Expanded(child: Text('No pudimos cargar los servicios.')),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(clinicActiveServicesProvider(clinic.id)),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          _ => const LinearProgressIndicator(),
        },
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service});

  final ClinicService service;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(service.nombre),
      subtitle: Text('${service.categoria.label} · ${service.duracionMin} min'),
      trailing: Text(
        _cop(service.precio),
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
