import 'dart:async' show TimeoutException;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import '../core/auth_error_mapper.dart';

/// Screen opened from "نسيت كلمة المرور؟" on the login screen.
/// The user enters their email and Supabase sends a password-recovery link.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  /// Pre-filled from the login screen's email field, if the user typed one.
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();
  late final TextEditingController emailController;

  bool isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  static const _timeout = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'صيغة البريد الإلكتروني غير صحيحة');
      return;
    }

    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.resetPassword(email).timeout(_timeout);
      if (!mounted) return;
      setState(() => _emailSent = true);
    } on TimeoutException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = friendlyAuthErrorMessage(e,
          fallback: 'استغرق الطلب وقتاً طويلاً، تحقّق من اتصالك وحاول مرة أخرى'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = friendlyAuthErrorMessage(
          e, fallback: 'تعذّر إرسال رابط الاستعادة، حاول مرة أخرى'));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة المرور'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _emailSent ? _buildSuccess() : _buildForm(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildForm() {
    return [
      const SizedBox(height: 10),
      const Text('نسيت كلمة المرور؟ 🔑', style: AppTextStyles.h2),
      const SizedBox(height: 6),
      const Text(
        'أدخل بريدك الإلكتروني وسنرسل لك رابطاً لإعادة تعيين كلمة المرور',
        style: AppTextStyles.body,
      ),
      const SizedBox(height: 26),
      AppTextField(
        controller: emailController,
        label: 'البريد الإلكتروني',
        icon: Icons.email_outlined,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 18),
      PrimaryButton(
        text: 'إرسال رابط الاستعادة',
        isLoading: isLoading,
        onPressed: _submit,
      ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 14),
        AuthErrorBanner(
          message: _errorMessage!,
          isNetwork: _errorMessage!.contains('الاتصال') ||
              _errorMessage!.contains('وقتاً'),
          onRetry: _submit,
        ),
      ],
      const SizedBox(height: 14),
      Center(
        child: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('العودة لتسجيل الدخول',
              style: TextStyle(color: AppColors.primaryDark)),
        ),
      ),
    ];
  }

  List<Widget> _buildSuccess() {
    return [
      const SizedBox(height: 40),
      const Icon(Icons.mark_email_read_outlined,
          size: 72, color: AppColors.primaryDark),
      const SizedBox(height: 20),
      const Text('تم إرسال الرابط ✉️',
          style: AppTextStyles.h2, textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Text(
        'إذا كان البريد ${emailController.text.trim()} مسجّلاً لدينا، فستصلك رسالة تحتوي على رابط إعادة تعيين كلمة المرور. تحقّق أيضاً من مجلد الرسائل غير المرغوب فيها.',
        style: AppTextStyles.body,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 30),
      PrimaryButton(
        text: 'العودة لتسجيل الدخول',
        onPressed: () => Navigator.pop(context),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: () => setState(() => _emailSent = false),
          child: const Text('لم تصلك الرسالة؟ أعد المحاولة',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ),
    ];
  }
}

// ── Shared inline error widget (same pattern as login/signup screens) ────────

/// Public version of the auth error banner so the recovery screens can reuse
/// it. Displays a retry link for network / timeout errors.
class AuthErrorBanner extends StatelessWidget {
  final String message;
  final bool isNetwork;
  final VoidCallback onRetry;

  const AuthErrorBanner({
    super.key,
    required this.message,
    required this.isNetwork,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.danger.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: AppTextStyles.small.copyWith(
                      color: AppColors.danger,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  if (isNetwork) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onRetry,
                      child: Text(
                        'إعادة المحاولة',
                        style: AppTextStyles.small.copyWith(
                          color: AppColors.danger,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
