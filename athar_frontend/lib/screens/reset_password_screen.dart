import 'dart:async' show TimeoutException;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import '../core/auth_error_mapper.dart';
import 'forgot_password_screen.dart' show AuthErrorBanner;
import 'main_navigation_screen.dart';

/// Opened automatically when the user follows the password-recovery link from
/// the reset email (Supabase fires AuthChangeEvent.passwordRecovery — see
/// main.dart). The user is authenticated with a temporary recovery session,
/// so we can set the new password via `updateUser`.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _authService = AuthService();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  bool isLoading = false;
  String? _errorMessage;

  static const _timeout = Duration(seconds: 15);

  @override
  void dispose() {
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = passwordController.text;
    if (password.length < 6) {
      setState(
          () => _errorMessage = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }
    if (password != confirmController.text) {
      setState(() => _errorMessage = 'كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.updatePassword(password).timeout(_timeout);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح ✅')),
      );
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
          e, fallback: 'تعذّر تغيير كلمة المرور، حاول مرة أخرى'));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('تعيين كلمة مرور جديدة'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              const Text('كلمة مرور جديدة 🔒', style: AppTextStyles.h2),
              const SizedBox(height: 6),
              const Text('اختر كلمة مرور جديدة لحسابك',
                  style: AppTextStyles.body),
              const SizedBox(height: 26),
              AppTextField(
                controller: passwordController,
                label: 'كلمة المرور الجديدة',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: confirmController,
                label: 'تأكيد كلمة المرور',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                text: 'حفظ كلمة المرور',
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
            ],
          ),
        ),
      ),
    );
  }
}
