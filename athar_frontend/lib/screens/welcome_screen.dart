import 'dart:async' show TimeoutException;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Public, shared demo account — anyone can explore the app with real,
  // pre-seeded data without signing up. Kept in sync with scripts/seed_demo.py.
  static const _demoEmail = 'demo@athar-fintech.app';
  static const _demoPassword = 'AtharDemo2026';

  final _auth = AuthService();
  bool _isDemoLoading = false;
  String? _error;

  Future<void> _enterDemo() async {
    setState(() {
      _isDemoLoading = true;
      _error = null;
    });
    try {
      await _auth
          .signIn(email: _demoEmail, password: _demoPassword)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (route) => false,
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = 'استغرق الطلب وقتاً طويلاً، حاول مرة أخرى');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذّر فتح الحساب التجريبي، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _isDemoLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEFF6F1), Colors.white, Color(0xFFE6F0EA)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              children: [
                const Spacer(flex: 3),
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryLight.withOpacity(0.4), width: 1.4),
                    boxShadow: [
                      BoxShadow(color: AppColors.primaryDark.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: const Center(child: Text('🌴', style: TextStyle(fontSize: 50))),
                ),
                const SizedBox(height: 24),
                const Text('أثَر', style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 42, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                const SizedBox(height: 10),
                const Text('ازرع عادتك المالية.. واحصد مزرعتك', textAlign: TextAlign.center, style: AppTextStyles.body),
                const Spacer(flex: 4),

                // ── One-tap demo entry (highlighted primary action) ──────────
                PrimaryButton(
                  text: 'جرّب التطبيق الآن (حساب تجريبي)',
                  icon: Icons.play_circle_fill_rounded,
                  isLoading: _isDemoLoading,
                  onPressed: _enterDemo,
                ),
                const SizedBox(height: 6),
                const Text(
                  'ادخل مباشرة ببيانات جاهزة تعرض كل مزايا التطبيق',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.small,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.small.copyWith(color: AppColors.danger),
                  ),
                ],

                const SizedBox(height: 18),
                SecondaryButton(
                  text: 'إنشاء حساب جديد',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('لديك حساب؟ تسجيل الدخول',
                      style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
