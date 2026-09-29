/// Configuración de compilación. Se cambia con --dart-define, por ejemplo:
/// `flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=192.168.1.20`
abstract final class Env {
  /// Conecta la app a Firebase Emulator Suite en vez de a los servicios reales.
  static const bool useEmulators = bool.fromEnvironment('USE_EMULATORS');

  /// 10.0.2.2 es el "localhost" del PC visto desde el emulador de Android.
  /// En un celular físico, usa la IP local del PC.
  static const String emulatorHost =
      String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');

  /// Región de Cloud Functions. Debe coincidir con functions/src/config.ts.
  static const String functionsRegion = 'us-east1';

  /// Opcional: client ID OAuth de tipo "Web" del proyecto Firebase.
  /// Normalmente google_sign_in lo lee de google-services.json.
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
}
