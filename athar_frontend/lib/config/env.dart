/// Build-time configuration, injected via --dart-define.
///
/// Example:
///   flutter run \
///     --dart-define=API_BASE_URL=https://athar-api.ondigitalocean.app \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=xxxxx
class Env {
  Env._();

  /// Base URL of the FastAPI backend. Defaults to the Android emulator's
  /// host-loopback address for local development.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://athar-backend-s8tm.onrender.com',
  );

  /// Supabase project URL. Client-side auth ONLY — never the service key.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon/public key. Safe for client distribution.
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
