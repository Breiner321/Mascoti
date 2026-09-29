import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/domain/app_user.dart';
import '../../../core/widgets/module_placeholder.dart';

class AppointmentsPage extends ConsumerWidget {
  const AppointmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider)?.role;
    return role == UserRole.clinica
        ? const ModulePlaceholder(
            title: 'Solicitudes pendientes',
            description: 'Aprobar o rechazar las citas solicitadas por los dueños.',
            requirements: ['RF-14 · semana 4'],
          )
        : const ModulePlaceholder(
            title: 'Mis citas',
            description: 'Agendar, ver y cancelar citas (mockup "Agendar cita").',
            requirements: ['RF-14 · semana 4', 'RF-13 · semana 4'],
          );
  }
}
