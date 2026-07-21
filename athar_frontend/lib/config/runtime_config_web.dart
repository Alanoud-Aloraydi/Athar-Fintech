/// Web implementation of runtime configuration lookup.
///
/// The backend injects a small `<script>window.atharEnv = {...}</script>` into
/// index.html at serve time (see backend/app/main.py), carrying the public
/// Supabase URL + anon key from the server's own environment. This lets the
/// same compiled web bundle run on any host without baking secrets in at
/// build time — which matters on platforms (e.g. Render) that don't expose
/// env vars as Docker build args.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

String? runtimeConfig(String key) {
  final envAny = globalContext.getProperty('atharEnv'.toJS);
  if (envAny.isUndefinedOrNull) return null;
  final valAny = (envAny as JSObject).getProperty(key.toJS);
  if (valAny.isUndefinedOrNull) return null;
  final s = (valAny as JSString).toDart;
  return s.isEmpty ? null : s;
}
