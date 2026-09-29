import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

/// Agenda de la clínica (mockup VISTA DE TIENDA, "Mi día").
class ClinicAgendaPage extends StatelessWidget {
  const ClinicAgendaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Mi día',
      description: 'Calendario mensual y franjas horarias de la clínica.',
      requirements: ['RF-04 · semana 2', 'RF-06 · semana 2'],
    );
  }
}
