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
}
