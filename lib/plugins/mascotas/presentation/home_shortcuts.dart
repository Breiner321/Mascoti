import 'package:flutter/material.dart';

import '../../../core/kernel/plugin_registry.dart';
import '../mascotas_routes.dart';

/// Destino de un acceso del home. Se identifica por id de plugin y ruta, sin
/// importar el plugin (regla del microkernel).
@immutable
class HomeShortcut {
  const HomeShortcut({
    required this.label,
    required this.icon,
    required this.pluginId,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String pluginId;
  final String path;

  /// Habilitado solo si el plugin está activo y ya aporta la ruta; si no, el
  /// acceso se muestra como "Próximamente".
  bool isAvailable(PluginRegistry registry) =>
      registry.isEnabled(pluginId) && registry.hasRoute(path);
}

/// Tarjetas y accesos del mockup VISTA CLIENTE.
abstract final class HomeShortcuts {
  static const schedule = HomeShortcut(
    label: 'Agendar cita',
    icon: Icons.event_available_outlined,
    pluginId: 'reservas',
    path: '/reservas/nueva',
  );

  static const healthCard = HomeShortcut(
    label: 'Vacunas y controles',
    icon: Icons.vaccines_outlined,
    pluginId: 'mascotas',
    path: MascotasRoutes.healthCard,
  );

  static const newPet = HomeShortcut(
    label: 'Registra tu primera mascota',
    icon: Icons.add,
    pluginId: 'mascotas',
    path: MascotasRoutes.newPet,
  );

  static const petList = HomeShortcut(
    label: 'Mis mascotas',
    icon: Icons.menu,
    pluginId: 'mascotas',
    path: MascotasRoutes.petList,
  );

  /// Sección "Accesos" (2 × 2).
  static const access = [
    HomeShortcut(
      label: 'Mapa cercano',
      icon: Icons.location_on_outlined,
      pluginId: 'directorio',
      path: '/directorio',
    ),
    HomeShortcut(
      label: 'Tienda',
      icon: Icons.shopping_bag_outlined,
      pluginId: 'tienda',
      path: '/tienda',
    ),
    schedule,
    emergency,
  ];

  static const emergency = HomeShortcut(
    label: 'Emergencia',
    icon: Icons.phone_in_talk_outlined,
    pluginId: 'sos',
    path: '/sos',
  );

  /// Sección "Servicios": agendar con la categoría preseleccionada (RF-05).
  static const services = [
    HomeShortcut(
      label: 'Consulta',
      icon: Icons.medical_services_outlined,
      pluginId: 'reservas',
      path: '/reservas/nueva?categoria=consulta_general',
    ),
    HomeShortcut(
      label: 'Peluquería',
      icon: Icons.content_cut,
      pluginId: 'reservas',
      path: '/reservas/nueva?categoria=peluqueria',
    ),
    HomeShortcut(
      label: 'Vacunas',
      icon: Icons.vaccines_outlined,
      pluginId: 'reservas',
      path: '/reservas/nueva?categoria=vacunacion',
    ),
  ];
}
