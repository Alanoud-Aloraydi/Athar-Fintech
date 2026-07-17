import 'dart:async' show TimeoutException;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import '../core/auth_error_mapper.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'main_navigation_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  /// Non-null when an auth attempt failed. Shown inline below the form.
  /// Cleared automatically at the start of every new attempt.
  String? _errorMessage;

  static const _timeout = Duration(seconds: 15);

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Clear previous error and start loading.
    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService
          .signIn(
            email: emailController.text.trim(),
            password: passwordController.text,
          )
          .timeout(_timeout);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (route) => false,
      );
    } on TimeoutException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = friendlyAuthErrorMessage(e,
          fallback: 'استغرق الطلب وقتاً طويلاً، تحقّق من اتصالك وحاول مرة أخرى'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = friendlyAuthErrorMessage(
          e, fallback: 'تعذّر تسجيل الدخول، حاول مرة أخرى'));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              const Text('أهلاً بعودتك 👋', style: AppTextStyles.h2),
              const SizedBox(height: 6),
              const Text('سجّل دخولك لمتابعة رحلتك المالية',
                  style: AppTextStyles.body),
              const SizedBox(height: 26),
              AppTextField(
                controller: emailController,
                label: 'البريد الإلكتروني',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: passwordController,
                label: 'الرقم السري',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ForgotPasswordScreen(
                          initialEmail: emailController.text.trim()),
                    ),
                  ),
                  child: const Text('نسيت كلمة المرور؟',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                  text: 'دخول', isLoading: isLoading, onPressed: _submit),

              // ── Inline error message ──────────────────────────────────
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                _AuthErrorBanner(
                  message: _errorMessage!,
                  isNetwork: _errorMessage!.contains('الاتصال') ||
                      _errorMessage!.contains('وقتاً'),
                  onRetry: _submit,
                ),
              ],

              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen())),
                  child: const Text('ليس لديك حساب؟ سجل الآن',
                      style: TextStyle(color: AppColors.primaryDark)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared inline error widget ───────────────────────────────────────────────

/// Shown below the submit button when an auth attempt fails.
/// Displays a retry button for network / timeout errors.
class _AuthErrorBanner extends StatelessWidget {
  final String message;
  final bool isNetwork;
  final VoidCallback onRetry;

  const _AuthErrorBanner({
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
