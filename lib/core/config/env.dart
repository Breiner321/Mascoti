/// Configuración de compilación. Se cambia con --dart-define, por ejemplo:
/// `flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=192.168.1.20`
abstract final class Env {
  /// Conecta la app a Firebase Emulator Suite en vez de a los servicios reales.
  static const bool useEmulators = bool.fromEnvironment('USE_EMULATORS');

  /// 10.0.2.2 es el "localhost" del PC visto desde el emulador de Android.
  /// En un celular físico, usa la IP local del PC.
  static const String emulatorHost =
      String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');

  /// Proyecto de Supabase (Storage + Edge Functions). Se pasan con
  /// `--dart-define-from-file=env/dev.json` (ver docs/configuracion-inicial.md).
  /// La publishable key (`sb_publishable_...`) es pública: la protegen las
  /// políticas de Supabase. Nunca usar aquí la secret/service_role key.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Opcional: client ID OAuth de tipo "Web" del proyecto Firebase.
  /// Normalmente google_sign_in lo lee de google-services.json.
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
}
