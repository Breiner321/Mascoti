import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/domain/clinic_service.dart';
import '../../../core/theme/app_theme.dart';
import 'clinic_providers.dart';
import 'service_card.dart';
import 'service_form_sheet.dart';

/// Catálogo de servicios de la clínica (RF-05).
class ClinicServicesPage extends ConsumerStatefulWidget {
  const ClinicServicesPage({super.key});

  @override
  ConsumerState<ClinicServicesPage> createState() => _ClinicServicesPageState();
}

class _ClinicServicesPageState extends ConsumerState<ClinicServicesPage> {
  /// Ids ya mostrados: los que aparecen después entran con animación.
  Set<String>? _seen;

  /// Ids que llegaron después de la primera carga: se muestran con animación
  /// de entrada (que corre una sola vez por tarjeta).
  final Set<String> _fresh = {};

  /// Tarjetas que el usuario deslizó; se ocultan ya, sin esperar al stream.
  final Set<String> _dismissed = {};

  Future<void> _openForm(String clinicId, [ClinicService? service]) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showServiceFormSheet(context, clinicId: clinicId, service: service);
    if (saved != true) return;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
          service == null ? 'Servicio creado' : 'Servicio actualizado',
          style: const TextStyle(color: AppColors.onPrimary),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(String clinicId, ClinicService service) async {
    final repo = ref.read(servicesRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final activeAppointments = await repo.activeAppointmentsCount(clinicId, service.id);
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar servicio'),
        content: Text(
          activeAppointments > 0
              ? 'Este servicio tiene $activeAppointments citas activas. Se ocultará '
                  'del catálogo pero las citas existentes no se verán afectadas'
              : '¿Eliminar "${service.nombre}"? Se ocultará del catálogo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await repo.deactivate(clinicId, service.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar el servicio. Intenta de nuevo.')),
      );
      return false;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Servicio eliminado')));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId;
    if (clinicId == null) {
      return const Center(child: Text('Tu cuenta no tiene una clínica asociada.'));
    }
    final services = ref.watch(clinicServicesProvider(clinicId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(clinicId),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Servicio'),
      ),
      body: switch (services) {
        AsyncData(:final value) => _buildList(clinicId, value),
        AsyncError() => _Centered(
            icon: Icons.cloud_off,
            text: 'No se pudieron cargar tus servicios.',
            action: FilledButton(
              onPressed: () => ref.invalidate(clinicServicesProvider(clinicId)),
              child: const Text('Reintentar'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildList(String clinicId, List<ClinicService> all) {
    final services = [
      for (final s in all)
        if (!_dismissed.contains(s.id)) s,
    ];
    final seen = _seen ??= {for (final s in services) s.id};

    if (services.isEmpty) {
      return const _Centered(
        icon: Icons.medical_services_outlined,
        text: 'Aún no tienes servicios. Agrega el primero',
      );
    }

    return ListView.separated(
      // Espacio abajo para que el botón flotante no tape la última tarjeta.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final service = services[i];
        final card = ServiceCard(
          key: ValueKey(service.id),
          service: service,
          onTap: () => _openForm(clinicId, service),
          confirmDelete: () => _confirmDelete(clinicId, service),
          onDeleted: () => setState(() => _dismissed.add(service.id)),
        );
        if (seen.add(service.id)) _fresh.add(service.id);
        if (!_fresh.contains(service.id)) return card;
        return _AppearAnimation(key: ValueKey('appear-${service.id}'), child: card);
      },
    );
  }
}

/// Entrada de una tarjeta nueva (RF-05 paso 8): se despliega y aparece.
class _AppearAnimation extends StatefulWidget {
  const _AppearAnimation({super.key, required this.child});

  final Widget child;

  @override
  State<_AppearAnimation> createState() => _AppearAnimationState();
}

class _AppearAnimationState extends State<_AppearAnimation>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward();
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: _curve,
        child: FadeTransition(opacity: _curve, child: widget.child),
      );
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
