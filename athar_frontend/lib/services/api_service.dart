import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';
import '../models/models.dart';

/// Thrown for any non-2xx response. Carries the HTTP status code plus the
/// backend's `detail` message (FastAPI's HTTPException shape) so screens can
/// distinguish, e.g., 409 goal conflicts from 502 upstream failures.
///
/// `message` mirrors the backend's raw (English, technical) detail text and
/// is kept only for logs/debugging -- UI code should use [arabicMessage]
/// instead of [message] so users always see a safe, Arabic message.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Safe, Arabic, user-facing messages for [ApiException]. Never surfaces the
/// backend's raw `detail` text -- only a small set of known, deliberately
/// generic messages keyed by HTTP status code.
extension ApiExceptionArabic on ApiException {
  String get arabicMessage {
    switch (statusCode) {
      case 401:
        return 'انتهت صلاحية الجلسة، يرجى تسجيل الدخول مرة أخرى';
      case 403:
        return 'لا تملك صلاحية الوصول لهذا العنصر';
      case 404:
        return 'العنصر المطلوب غير موجود';
      case 409:
        // The only 409 today is "you already have an active goal" -- this
        // is a real, useful business rule, not leaked internals.
        return 'لديك هدف مالي نشط بالفعل، يجب إكماله أو أرشفته قبل إنشاء هدف جديد';
      case 502:
      case 503:
        return 'تعذّر الاتصال بالخادم حالياً، حاول مرة أخرى بعد قليل';
      case 500:
        return 'حدث خطأ غير متوقع في الخادم، حاول مرة أخرى';
      case 400:
      case 422:
        return 'يرجى التحقق من البيانات المدخلة والمحاولة مرة أخرى';
      default:
        return 'حدث خطأ غير متوقع، حاول مرة أخرى';
    }
  }
}

/// For use in `FutureBuilder`/`snapshot.error` contexts. Unlike
/// [ApiExceptionArabic.arabicMessage] (which only handles [ApiException]),
/// `snapshot.error` can also be a raw Dart/network exception (timeouts,
/// DNS failures, JSON parsing errors, ...) if the request never reached
/// the backend at all -- those raw exception types are NOT safe to show
/// verbatim either, so this always returns a safe Arabic string.
String friendlyLoadErrorMessage(Object? error) {
  if (error is ApiException) return error.arabicMessage;
  return 'تعذّر الاتصال بالخادم، تحقّق من اتصالك بالإنترنت وحاول مرة أخرى';
}

/// Talks to the Athar FastAPI backend. All endpoint paths, request/response
/// shapes, and aliases below are copied verbatim from the backend's
/// Presentation-layer routers and schemas — the backend is the single
/// source of truth, this class does not reshape or simplify anything.
class ApiService {
  final String baseUrl;

  ApiService({String? baseUrl}) : baseUrl = (baseUrl ?? Env.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');

  /// Every request must prove who's calling -- the backend now verifies
  /// this token and rejects any request where it doesn't match the
  /// user_id being accessed (see `app/presentation/auth.py`). Without
  /// this header, every call below will get a 401 from the backend.
  Map<String, String> get _authHeaders {
    final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null) {
      // Should not normally happen -- every screen that calls ApiService
      // is behind AuthGate -- but fail loudly rather than silently
      // sending an unauthenticated request.
      throw ApiException(401, 'Not authenticated.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };
  }

  // --- Analytics -----------------------------------------------------------

  /// GET /analytics/{user_id} -> DashboardSummaryDTO
  Future<DashboardSummary> getDashboardSummary(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/analytics/$userId'), headers: _authHeaders);
    _checkStatus(res);
    return DashboardSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // --- Oasis -----------------------------------------------------------------

  /// GET /oasis/{user_id} -> OasisStateDTO
  Future<OasisState> getOasisState(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/oasis/$userId'), headers: _authHeaders);
    _checkStatus(res);
    return OasisState.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // --- Goals -----------------------------------------------------------------

  /// GET /goals/{user_id}/active -> GoalResponseDTO | null
  Future<Goal?> getActiveGoal(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/goals/$userId/active'), headers: _authHeaders);
    _checkStatus(res);
    if (res.body.trim() == 'null' || res.body.trim().isEmpty) return null;
    return Goal.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// POST /goals/{user_id} -> 201 GoalResponseDTO | 409 if one is already ACTIVE
  Future<Goal> createGoal({
    required String userId,
    required String title,
    required double targetAmount,
    required AppCategory category,
    DateTime? deadline,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/goals/$userId'),
      headers: _authHeaders,
      body: jsonEncode({
        'title': title,
        'target_amount': targetAmount,
        'category': category.apiValue,
        if (deadline != null) 'deadline': _dateOnly(deadline),
      }),
    );
    _checkStatus(res);
    return Goal.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// PATCH /goals/{user_id}/{goal_id}/status -> GoalResponseDTO
  /// [newStatus] must be exactly "COMPLETED" or "ARCHIVED" (backend Literal).
  Future<Goal> transitionGoalStatus({
    required String userId,
    required String goalId,
    required String newStatus,
  }) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/goals/$userId/$goalId/status'),
      headers: _authHeaders,
      body: jsonEncode({'status': newStatus}),
    );
    _checkStatus(res);
    return Goal.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // --- Transactions ------------------------------------------------------------

  /// POST /transactions/ -> 201 TransactionResponseDTO
  ///
  /// NOTE the trailing slash: the router is mounted at prefix "/transactions"
  /// with an endpoint path of "/", so the real route is "/transactions/".
  /// Category is intentionally NOT sent — it's derived server-side by the
  /// Categorization Engine (any "category" key would be silently ignored).
  Future<TransactionResult> createTransaction({
    required String userId,
    required double amount,
    required String description,
    required String type, // "EXPENSE" | "INCOME"
    String? idempotencyKey,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/transactions/'),
      headers: _authHeaders,
      body: jsonEncode({
        'user_id': userId,
        'amount': amount,
        'description': description,
        'type': type,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      }),
    );
    _checkStatus(res);
    return TransactionResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // --- Helpers -----------------------------------------------------------------

  String _dateOnly(DateTime d) => d.toIso8601String().split('T').first;

  void _checkStatus(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;

    String message = 'حدث خطأ غير متوقع (${res.statusCode})';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['detail'] != null) {
        message = decoded['detail'].toString();
      }
    } catch (_) {
      // Non-JSON error body (e.g. a raw 502 from the platform) — fall back
      // to the generic message above rather than surfacing raw HTML/text.
    }
    throw ApiException(res.statusCode, message);
  }
}