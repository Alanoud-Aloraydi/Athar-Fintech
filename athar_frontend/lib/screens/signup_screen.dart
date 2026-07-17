import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _authService = AuthService();

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  bool agreedToTerms = false;
  bool agreedToDataLink = false;

  bool get canSubmit => agreedToTerms && agreedToDataLink && !isLoading;

  Future<void> _submit() async {
    if (!canSubmit) return;
    setState(() => isLoading = true);
    try {
      await _authService.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
        metadata: {
          'first_name': firstNameController.text.trim(),
          'last_name': lastNameController.text.trim(),
          'phone': phoneController.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر إنشاء الحساب: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('مرحباً بك في أثَر 🌴', style: AppTextStyles.h2),
              const SizedBox(height: 6),
              const Text('أنشئ حسابك للبدء في تتبّع أهدافك المالية', style: AppTextStyles.body),
              const SizedBox(height: 26),
              AppTextField(controller: firstNameController, label: 'الاسم الأول', icon: Icons.person_outline),
              const SizedBox(height: 14),
              AppTextField(controller: lastNameController, label: 'الاسم الثاني', icon: Icons.person_outline),
              const SizedBox(height: 14),
              AppTextField(controller: phoneController, label: 'رقم الجوال', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              AppTextField(controller: emailController, label: 'البريد الإلكتروني', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 14),
              AppTextField(controller: passwordController, label: 'الرقم السري', icon: Icons.lock_outline, obscureText: true),
              const SizedBox(height: 22),
              SectionCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  children: [
                    ConsentCheckboxTile(
                      value: agreedToTerms,
                      onChanged: (v) => setState(() => agreedToTerms = v ?? false),
                      text: 'أوافق على الشروط والأحكام وسياسة الخصوصية الخاصة بتطبيق أثَر',
                    ),
                    const Divider(height: 4, color: AppColors.border),
                    ConsentCheckboxTile(
                      value: agreedToDataLink,
                      onChanged: (v) => setState(() => agreedToDataLink = v ?? false),
                      text: 'أوافق على ربط حسابي البنكي عبر خدمة المصرفية المفتوحة لتحليل صرفي وادخاري',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              PrimaryButton(text: 'إنشاء الحساب', isLoading: isLoading, onPressed: canSubmit ? _submit : null),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('لديك حساب بالفعل؟ سجل دخولك', style: TextStyle(color: AppColors.primaryDark)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
