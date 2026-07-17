import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'signup_screen.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

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
                PrimaryButton(
                  text: 'إنشاء حساب جديد',
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  text: 'تسجيل الدخول',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
