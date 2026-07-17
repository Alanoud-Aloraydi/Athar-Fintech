import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around the Supabase auth client (anon key, client-side only).
/// The backend's service_role key is never referenced here.
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  /// The UUID every backend endpoint is keyed on (`/analytics/{user_id}`,
  /// `/goals/{user_id}`, `/oasis/{user_id}`, and the transaction payload's
  /// `user_id` field).
  String? get currentUserId => currentUser?.id;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) {
    return _client.auth.signUp(email: email, password: password, data: metadata);
  }

  Future<AuthResponse> signIn({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Sends a password-recovery email via Supabase.
  ///
  /// On web the email's link redirects back to this app's own origin, where
  /// the Supabase client fires an [AuthChangeEvent.passwordRecovery] event
  /// (handled in main.dart) that opens the "set new password" screen.
  /// NOTE: the origin must also be whitelisted under
  /// Authentication → URL Configuration → Redirect URLs in the Supabase
  /// dashboard for the redirect to work.
  Future<void> resetPassword(String email) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }

  /// Sets a new password for the currently-authenticated user (used after
  /// following the recovery link from the reset email).
  Future<UserResponse> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
