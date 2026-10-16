import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/module_placeholder.dart';
import '../clinica_routes.dart';

/// Agenda de la clínica (mockup VISTA DE TIENDA, "Mi día").
class ClinicAgendaPage extends StatelessWidget {
  const ClinicAgendaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextButton.icon(
              onPressed: () => context.push(ClinicaRoutes.setup),
              icon: const Icon(Icons.tune),
              label: const Text('Perfil de atención'),
            ),
          ),
        ),
        const Expanded(
          child: ModulePlaceholder(
            title: 'Mi día',
            description: 'Calendario mensual y franjas horarias de la clínica.',
            requirements: ['RF-06 · semana 2'],
          ),
        ),
      ],
    );
  }
}
