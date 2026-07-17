import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import '../core/auth_error_mapper.dart';
import 'signup_screen.dart';
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

  Future<void> _submit() async {
    setState(() => isLoading = true);
    try {
      await _authService.signIn(email: emailController.text.trim(), password: passwordController.text);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      final message = friendlyAuthErrorMessage(e, fallback: 'تعذّر تسجيل الدخول، حاول مرة أخرى');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
              const Text('سجّل دخولك لمتابعة رحلتك المالية', style: AppTextStyles.body),
              const SizedBox(height: 26),
              AppTextField(controller: emailController, label: 'البريد الإلكتروني', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 14),
              AppTextField(controller: passwordController, label: 'الرقم السري', icon: Icons.lock_outline, obscureText: true),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('نسيت كلمة المرور؟', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton(text: 'دخول', isLoading: isLoading, onPressed: _submit),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                  child: const Text('ليس لديك حساب؟ سجل الآن', style: TextStyle(color: AppColors.primaryDark)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}