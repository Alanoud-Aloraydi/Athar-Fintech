/// Build-time configuration, injected via --dart-define.
///
/// Example:
///   flutter run \
///     --dart-define=API_BASE_URL=https://athar-api.ondigitalocean.app \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=xxxxx
class Env {
  Env._();

  /// Base URL of the FastAPI backend.
  ///
  /// On Replit: injected at `flutter build web` time by start.sh via
  ///   --dart-define=API_BASE_URL=https://<REPLIT_DEV_DOMAIN>
  /// FastAPI and Flutter web are served from the same origin (port 5000),
  /// so this URL is identical to the Flutter web's public URL — no CORS needed.
  ///
  /// Locally: set via --dart-define=API_BASE_URL=http://localhost:5000
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000',
  );

  /// Supabase project URL. Client-side auth ONLY — never the service key.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon/public key. Safe for client distribution.
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
