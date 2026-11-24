/// Rutas del plugin mascotas.
abstract final class MascotasRoutes {
  static const home = '/mascotas';

  /// Onboarding de 3 pasos del dueño (RF-01 paso 14).
  static const onboarding = '/mascotas/bienvenida';

  /// Registro de una mascota nueva.
  static const newPet = '/mascotas/nueva';

  /// Perfil y edición de una mascota. Llevan el prefijo `perfil/` para que
  /// `:petId` no se confunda con otras pantallas del plugin en
  /// PluginRegistry.hasRoute.
  static const profilePattern = '/mascotas/perfil/:petId';
  static const editPattern = '/mascotas/perfil/:petId/editar';

  static String profile(String petId) => '/mascotas/perfil/$petId';
  static String edit(String petId) => '/mascotas/perfil/$petId/editar';

  /// Pestaña "Documentos" de la ficha: placa QR (RF-17) y carnet PDF (RF-18).
  static String documents(String petId) => '/mascotas/perfil/$petId?tab=documentos';
}
