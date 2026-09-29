import 'package:flutter/material.dart';

import '../../../core/widgets/module_placeholder.dart';

/// Home del dueño (mockup VISTA CLIENTE, primera pantalla).
class OwnerHomePage extends StatelessWidget {
  const OwnerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Mis mascotas',
      description: 'Aquí irán la tarjeta de la mascota, la próxima cita, '
          'los accesos rápidos y los servicios.',
      requirements: ['Registro de mascotas · semana 2', 'RF-08 · semana 3'],
    );
  }
}
