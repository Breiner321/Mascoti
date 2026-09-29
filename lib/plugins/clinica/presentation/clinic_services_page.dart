import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

/// Catálogo de servicios de la clínica.
class ClinicServicesPage extends StatelessWidget {
  const ClinicServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Servicios',
      description: 'Crear, editar y desactivar servicios (vacunación, peluquería…).',
      requirements: ['RF-05 · semana 2'],
    );
  }
}
