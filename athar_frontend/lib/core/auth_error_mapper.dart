import 'dart:async' show TimeoutException;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Converts any error thrown during a Supabase auth call (sign up, sign in,
/// update user, ...) into a safe, Arabic, user-facing message.
///
/// IMPORTANT: this NEVER returns the raw exception text (`e.toString()`),
/// the exception class name, the HTTP status code, or the internal Supabase
/// error `code`. Showing that raw text to the user (e.g.
/// "AuthApiException(message: Invalid API key, statusCode: 401, code: null)")
/// leaks implementation details that are useless to a normal user and
/// potentially useful to an attacker probing the app.
///
/// The raw error is still logged via [debugPrint] so it's visible in the
/// developer console / `flutter logs` during development, just never shown
/// inside the UI.
String friendlyAuthErrorMessage(Object error, {String? fallback}) {
  // Always log the real error for debugging -- this only prints to the
  // local dev console / CI logs, it is never rendered in the app UI.
  debugPrint('Auth error: $error');

  // ── Network / timeout errors (not AuthException) ────────────────────────
  // These happen before Supabase even responds, so they don't come wrapped
  // in AuthException.
  if (error is TimeoutException) {
    return 'استغرق الطلب وقتاً طويلاً، تحقّق من اتصالك وحاول مرة أخرى';
  }

  // ── Supabase AuthException ───────────────────────────────────────────────
  if (error is AuthException) {
    final msg = error.message.toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
    }

    if (msg.contains('already registered') ||
        msg.contains('already exists') ||
        msg.contains('user_already_exists')) {
      return 'هذا البريد الإلكتروني مسجّل مسبقاً، جرّب تسجيل الدخول بدلاً من ذلك';
    }

    if (msg.contains('password should be at least') ||
        (msg.contains('password') && msg.contains('character'))) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }

    if (msg.contains('unable to validate email') ||
        msg.contains('invalid email') ||
        msg.contains('is invalid')) {
      return 'صيغة البريد الإلكتروني غير صحيحة';
    }

    if (msg.contains('email not confirmed') ||
        msg.contains('email_not_confirmed')) {
      return 'يجب تفعيل بريدك الإلكتروني أولاً قبل تسجيل الدخول';
    }

    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return 'محاولات كثيرة جداً، حاول مرة أخرى بعد قليل';
    }

    if (msg.contains('invalid api key') ||
        msg.contains('network') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection')) {
      return 'تعذّر الاتصال بالخادم، تحقّق من اتصالك بالإنترنت وحاول مرة أخرى';
    }
  }

  // ── Catch-all: check raw message for network keywords ───────────────────
  // Covers:
  //  • Flutter Web   — "Failed to fetch", "XMLHttpRequest error"
  //  • Native        — dart:io SocketException stringified as
  //                    "SocketException: Failed host lookup: '...'"
  //                    or "SocketException: Connection refused"
  //                    (dart:io is NOT imported here to keep this file
  //                    web-safe; we match on the string representation)
  final raw = error.toString().toLowerCase();
  if (raw.contains('failed to fetch') ||
      raw.contains('xmlhttprequest') ||
      raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection refused') ||
      raw.contains('network') ||
      raw.contains('connection')) {
    return 'تعذّر الاتصال بالخادم، تحقّق من اتصالك بالإنترنت وحاول مرة أخرى';
  }

  // Unknown / unexpected error shape -- never surface it raw.
  return fallback ?? 'حدث خطأ غير متوقع، حاول مرة أخرى';
}