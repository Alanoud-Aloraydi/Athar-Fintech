/// Build-time / run-time configuration.
///
/// Values are resolved in this order:
///   1. Runtime config injected by the backend into index.html as
///      `window.atharEnv` (web only — see backend/app/main.py). This is what
///      makes a single compiled bundle work on any host without baking
///      secrets in at build time.
///   2. `--dart-define` values baked in at `flutter build web` time.
///   3. A sensible default (local dev).
///
/// Example (local build):
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=xxxxx
import 'runtime_config.dart' if (dart.library.js_interop) 'runtime_config_web.dart';

class Env {
  Env._();

  /// Base URL of the FastAPI backend.
  ///
  /// On web, [ApiService] resolves the host at runtime via `Uri.base`, so this
  /// is only used as a fallback / for non-web targets.
  static String get apiBaseUrl {
    final rt = runtimeConfig('API_BASE_URL');
    if (rt != null) return rt;
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:5000',
    );
  }

  /// Supabase project URL. Client-side auth ONLY — never the service key.
  static String get supabaseUrl {
    final rt = runtimeConfig('SUPABASE_URL');
    if (rt != null) return rt;
    return const String.fromEnvironment('SUPABASE_URL');
  }

  /// Supabase anon/public key. Safe for client distribution.
  static String get supabaseAnonKey {
    final rt = runtimeConfig('SUPABASE_ANON_KEY');
    if (rt != null) return rt;
    return const String.fromEnvironment('SUPABASE_ANON_KEY');
  }
}
