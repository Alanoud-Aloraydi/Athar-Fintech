/// Non-web stub for runtime configuration lookup.
///
/// On platforms without a JS `window` (mobile/desktop/tests) there is no
/// server-injected config, so this always returns null and callers fall back
/// to the compile-time `String.fromEnvironment` value.
String? runtimeConfig(String key) => null;
