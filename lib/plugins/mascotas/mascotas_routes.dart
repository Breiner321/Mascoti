/// Rutas del plugin mascotas.
abstract final class MascotasRoutes {
  static const home = '/mascotas';

  /// Onboarding de 3 pasos del dueño (RF-01 paso 14).
  static const onboarding = '/mascotas/bienvenida';

  // Pantallas de semanas siguientes: los accesos se ven como "Próximamente"
  // mientras estas rutas no existan (PluginRegistry.hasRoute).
  static const newPet = '/mascotas/nueva'; // semana 2
  static const petList = '/mascotas/lista'; // semana 2
  static const healthCard = '/mascotas/carnet'; // RF-08 / RF-18
}
