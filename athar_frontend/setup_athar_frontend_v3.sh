#!/usr/bin/env bash
# ============================================================================
# setup_athar_frontend_v3.sh
#
# Additive merge of Sarah's Dark Mode / Localization / Quick-Login UI into
# the existing ApiService/Supabase-integrated Athar frontend.
#
# This script ONLY writes files that are new or modified by this merge.
# Every other existing file (screens/login_screen.dart, signup_screen.dart,
# dashboard_screen.dart, farm_screen.dart, welcome_screen.dart,
# add_transaction_sheet.dart, goal_dialog.dart, main_navigation_screen.dart,
# services/api_service.dart, services/auth_service.dart, models/models.dart,
# config/env.dart) is left untouched on disk.
#
# Run from the athar_frontend/ project root.
# ============================================================================
set -euo pipefail

echo "==> Adding shared_preferences dependency to pubspec.yaml"
if ! grep -q "shared_preferences:" pubspec.yaml; then
  # Insert the new dependency right after intl: ^0.19.0
  sed -i.bak '/intl: \^0.19.0/a\
  shared_preferences: ^2.3.3' pubspec.yaml
  rm -f pubspec.yaml.bak
else
  echo "    shared_preferences already present, skipping"
fi

mkdir -p lib/core
mkdir -p lib/screens
mkdir -p lib/theme
mkdir -p lib/widgets

# ----------------------------------------------------------------------------
# lib/core/app_settings.dart  (NEW)
# ----------------------------------------------------------------------------
cat << 'EOF' > lib/core/app_settings.dart
import 'package:flutter/material.dart';

/// Global, in-memory app preferences: theme mode, locale, text scale.
///
/// Purely a local UX layer -- it never touches Supabase auth or the
/// FastAPI backend. Extracted from Sarah's main.dart so it can be shared
/// by both the app root and any screen that needs to read/mutate it.
class AppSettings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.light;
  Locale locale = const Locale('ar');
  double textScale = 1.0;

  bool get isDark => themeMode == ThemeMode.dark;
  bool get isArabic => locale.languageCode == 'ar';

  void toggleDarkMode(bool isDark) {
    themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setLanguage(String code) {
    locale = Locale(code);
    notifyListeners();
  }

  void setTextScale(double value) {
    textScale = value;
    notifyListeners();
  }
}

/// Process-wide singleton -- same pattern as `Supabase.instance`: one
/// instance, read anywhere via import.
final AppSettings appSettings = AppSettings();

/// Rebuilds [builder] whenever [appSettings] changes (dark mode / language /
/// text-size toggles). Wrap any screen that reads `appSettings` or
/// `context.colors` in this so it repaints live when settings change
/// elsewhere in the app.
class SettingsScope extends StatefulWidget {
  final WidgetBuilder builder;
  const SettingsScope({super.key, required this.builder});

  @override
  State<SettingsScope> createState() => _SettingsScopeState();
}

class _SettingsScopeState extends State<SettingsScope> {
  @override
  void initState() {
    super.initState();
    appSettings.addListener(_onChange);
  }

  @override
  void dispose() {
    appSettings.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
EOF
echo "    wrote lib/core/app_settings.dart"

# ----------------------------------------------------------------------------
# lib/core/strings.dart  (NEW)
# ----------------------------------------------------------------------------
cat << 'EOF' > lib/core/strings.dart
import 'app_settings.dart';

/// عربي / English UI strings -- single source of truth for both languages.
/// Extracted verbatim from Sarah's main.dart.
class Strings {
  static final Map<String, Map<String, String>> _v = {
    'ar': {
      'app_name': 'أثَر',
      'tagline': 'ازرع عاداتك المالية.. واحصد مزرعتك',
      'create_account': 'إنشاء حساب جديد',
      'login': 'تسجيل الدخول',
      'signup_title': 'إنشاء حساب',
      'signup_welcome': 'مرحباً بك في أثَر 🌴',
      'signup_subtitle': 'أنشئ حسابك للبدء في تتبع أهدافك المالية',
      'first_name': 'الاسم الأول',
      'last_name': 'الاسم الثاني',
      'phone': 'رقم الجوال',
      'email': 'البريد الإلكتروني',
      'password': 'الرقم السري',
      'terms_agree': 'أوافق على الشروط والأحكام وسياسة الخصوصية الخاصة بتطبيق أثَر',
      'data_link_agree': 'أوافق على ربط حسابي البنكي عبر خدمة المصرفية المفتوحة لتحليل صرفي وادخاري وبناء المزرعة',
      'create_account_btn': 'إنشاء الحساب',
      'have_account': 'لديك حساب بالفعل؟ سجل دخولك',
      'login_title': 'تسجيل الدخول',
      'welcome_back': 'أهلاً بعودتك 👋',
      'login_subtitle': 'سجّل دخولك لمتابعة رحلتك المالية',
      'forgot_password': 'نسيت كلمة المرور؟',
      'login_btn': 'دخول',
      'no_account': 'ليس لديك حساب؟ سجل الآن',
      'quick_login': 'دخول سريع',
      'quick_login_title': 'الدخول السريع',
      'quick_login_subtitle': 'أدخل رمز الدخول السريع المكوّن من 5 أرقام',
      'create_quick_login_title': 'إنشاء رمز الدخول السريع',
      'create_code_subtitle': 'اختر رمزاً مكوّناً من 5 أرقام لتسجيل الدخول بسرعة لاحقاً',
      'confirm_code_subtitle': 'أعد إدخال الرمز للتأكيد',
      'codes_dont_match': 'الرمزان غير متطابقين، حاول مرة أخرى',
      'quick_login_created': 'تم إنشاء رمز الدخول السريع بنجاح',
      'nav_farm': 'المزرعة',
      'nav_dashboard': 'لوحة البيانات',
      'nav_profile': 'حسابي',
      'farm_title': 'مزرعة أثَر',
      'farm_growing': 'مزرعتك في طريقها للنمو 🌱',
      'farm_desc': 'سيتم تصميم المزرعة الرقمية هنا لاحقاً، وستنمو تلقائياً كلما اقتربت من تحقيق أهدافك في الادخار',
      'dashboard_title': 'لوحة البيانات',
      'total_balance': 'الرصيد الإجمالي',
      'balance_note': 'يتم تحديثه تلقائياً عبر البنكية المفتوحة',
      'monthly_spending': 'الصرف الشهري',
      'monthly_saving': 'الادخار الشهري',
      'goal_progress': 'تقدمك نحو الهدف',
      'no_bank_linked': 'لم يتم ربط الحساب البنكي بعد',
      'spending_categories': 'أقسام الصرف',
      'cat_restaurants': 'مطاعم وكافيهات',
      'cat_shopping': 'تسوق',
      'cat_transport': 'مواصلات',
      'cat_bills': 'فواتير',
      'cat_other': 'أخرى',
      'profile_title': 'البيانات الشخصية',
      'account_section': 'الحساب',
      'app_section': 'التطبيق',
      'name': 'الاسم',
      'goals': 'أهدافي المالية',
      'notifications': 'الإشعارات',
      'settings': 'الإعدادات',
      'logout': 'تسجيل الخروج',
      'edit_personal_data': 'تعديل بياناتي الشخصية',
      'settings_personal_section': 'البيانات الشخصية',
      'appearance': 'المظهر',
      'dark_mode': 'الوضع الليلي',
      'language': 'اللغة',
      'arabic': 'العربية',
      'english': 'English',
      'text_size': 'حجم الخط',
      'size_small': 'صغير',
      'size_medium': 'متوسط',
      'size_large': 'كبير',
      'size_xlarge': 'كبير جداً',
      'security_section': 'الأمان',
      'create_quick_code_tile': 'إنشاء رمز الدخول السريع',
      'other_settings': 'إعدادات أخرى',
      'about_app': 'عن التطبيق',
      'delete_account': 'حذف الحساب',
      'save_changes': 'حفظ التعديلات',
      'saved_success': 'تم حفظ التعديلات بنجاح',
    },
    'en': {
      'app_name': 'Athar',
      'tagline': 'Grow your financial habits.. harvest your farm',
      'create_account': 'Create New Account',
      'login': 'Log In',
      'signup_title': 'Create Account',
      'signup_welcome': 'Welcome to Athar 🌴',
      'signup_subtitle': 'Create your account to start tracking your financial goals',
      'first_name': 'First Name',
      'last_name': 'Last Name',
      'phone': 'Phone Number',
      'email': 'Email',
      'password': 'Password',
      'terms_agree': "I agree to Athar's Terms & Conditions and Privacy Policy",
      'data_link_agree': 'I agree to link my bank account via Open Banking to analyze my spending and saving, and build my farm',
      'create_account_btn': 'Create Account',
      'have_account': 'Already have an account? Log in',
      'login_title': 'Log In',
      'welcome_back': 'Welcome back 👋',
      'login_subtitle': 'Log in to continue your financial journey',
      'forgot_password': 'Forgot password?',
      'login_btn': 'Log In',
      'no_account': "Don't have an account? Sign up",
      'quick_login': 'Quick Login',
      'quick_login_title': 'Quick Login',
      'quick_login_subtitle': 'Enter your 5-digit quick login code',
      'create_quick_login_title': 'Create Quick Login Code',
      'create_code_subtitle': 'Choose a 5-digit code to log in quickly next time',
      'confirm_code_subtitle': 'Re-enter the code to confirm',
      'codes_dont_match': "The codes don't match, try again",
      'quick_login_created': 'Quick login code created successfully',
      'nav_farm': 'Farm',
      'nav_dashboard': 'Dashboard',
      'nav_profile': 'Profile',
      'farm_title': 'Athar Farm',
      'farm_growing': 'Your farm is on its way to growing 🌱',
      'farm_desc': 'The digital farm will be designed here later, and will grow automatically as you get closer to your savings goals',
      'dashboard_title': 'Dashboard',
      'total_balance': 'Total Balance',
      'balance_note': 'Automatically updated via Open Banking',
      'monthly_spending': 'Monthly Spending',
      'monthly_saving': 'Monthly Saving',
      'goal_progress': 'Your Goal Progress',
      'no_bank_linked': 'No bank account linked yet',
      'spending_categories': 'Spending Categories',
      'cat_restaurants': 'Restaurants & Cafes',
      'cat_shopping': 'Shopping',
      'cat_transport': 'Transportation',
      'cat_bills': 'Bills',
      'cat_other': 'Other',
      'profile_title': 'Personal Info',
      'account_section': 'Account',
      'app_section': 'App',
      'name': 'Name',
      'goals': 'My Financial Goals',
      'notifications': 'Notifications',
      'settings': 'Settings',
      'logout': 'Log Out',
      'edit_personal_data': 'Edit My Personal Data',
      'settings_personal_section': 'Personal Data',
      'appearance': 'Appearance',
      'dark_mode': 'Dark Mode',
      'language': 'Language',
      'arabic': 'Arabic',
      'english': 'English',
      'text_size': 'Text Size',
      'size_small': 'Small',
      'size_medium': 'Medium',
      'size_large': 'Large',
      'size_xlarge': 'Extra Large',
      'security_section': 'Security',
      'create_quick_code_tile': 'Create Quick Login Code',
      'other_settings': 'Other Settings',
      'about_app': 'About the App',
      'delete_account': 'Delete Account',
      'save_changes': 'Save Changes',
      'saved_success': 'Changes saved successfully',
    },
  };

  static String t(String key) {
    return _v[appSettings.locale.languageCode]?[key] ?? _v['ar']![key] ?? key;
  }
}

String tr(String key) => Strings.t(key);
EOF
echo "    wrote lib/core/strings.dart"

# ----------------------------------------------------------------------------
# lib/theme/app_theme.dart  (APPEND -- existing AppColors/AppTextStyles/
# buildAppTheme() left 100% intact; existing screens keep compiling/rendering
# exactly as before)
# ----------------------------------------------------------------------------
cat << 'EOF' >> lib/theme/app_theme.dart

// ============================================================================
// --- Dark-mode-aware color API (additive) ------------------------------------
// Appended for the new Settings/EditProfile/QuickLogin screens and any
// widget that wants to react to appSettings.themeMode. Does NOT replace
// AppColors/AppTextStyles/buildAppTheme() above -- existing screens are
// unaffected.
// ============================================================================

class AppColorSet {
  final Color background;
  final Color surface;
  final Color primary;
  final Color primaryDark;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color success;
  final Color danger;
  final Color gold;

  const AppColorSet({
    required this.background,
    required this.surface,
    required this.primary,
    required this.primaryDark,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.success,
    required this.danger,
    required this.gold,
  });
}

const AppColorSet _lightColorSet = AppColorSet(
  background: Color(0xFFFFF8F4),
  surface: Color(0xFFFFFFFF),
  primary: Color(0xFFFF7A50),
  primaryDark: Color(0xFF16273F),
  accent: Color(0xFFC9C6EE),
  textPrimary: Color(0xFF16273F),
  textSecondary: Color(0xFF6E7A8A),
  border: Color(0xFFF0E3DB),
  success: Color(0xFF2E8B57),
  danger: Color(0xFFD9482F),
  gold: Color(0xFFC9A227),
);

const AppColorSet _darkColorSet = AppColorSet(
  background: Color(0xFF0B1220),
  surface: Color(0xFF141F33),
  primary: Color(0xFFFF8A5B),
  primaryDark: Color(0xFFFF7A50),
  accent: Color(0xFFC9C6EE),
  textPrimary: Color(0xFFF5F1EC),
  textSecondary: Color(0xFF9CA8B8),
  border: Color(0xFF223349),
  success: Color(0xFF4CAF7D),
  danger: Color(0xFFFF6B52),
  gold: Color(0xFFE0B94A),
);

extension AppColorContext on BuildContext {
  AppColorSet get colors =>
      Theme.of(this).brightness == Brightness.dark ? _darkColorSet : _lightColorSet;
}

class AppText {
  static const String fontFamily = 'Tajawal';

  static TextStyle h1(BuildContext c) => TextStyle(
      fontFamily: fontFamily, fontSize: 30, fontWeight: FontWeight.bold, color: c.colors.textPrimary);

  static TextStyle h2(BuildContext c) => TextStyle(
      fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.bold, color: c.colors.textPrimary);

  static TextStyle body(BuildContext c) =>
      TextStyle(fontFamily: fontFamily, fontSize: 15, color: c.colors.textSecondary, height: 1.6);

  static TextStyle label(BuildContext c) => TextStyle(
      fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600, color: c.colors.textPrimary);

  static TextStyle small(BuildContext c) =>
      TextStyle(fontFamily: fontFamily, fontSize: 12.5, color: c.colors.textSecondary, height: 1.5);
}

ThemeData buildTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? _darkColorSet : _lightColorSet;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.background,
    fontFamily: AppText.fontFamily,
    colorScheme: ColorScheme.fromSeed(seedColor: colors.primary, brightness: brightness),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
          fontFamily: AppText.fontFamily, fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? colors.primary : Colors.transparent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? colors.primary : null),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? colors.primary.withOpacity(0.4) : null),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      labelStyle: TextStyle(color: colors.textSecondary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.primary, width: 1.6)),
    ),
  );
}
EOF
echo "    appended dark-mode theme API to lib/theme/app_theme.dart"

# ----------------------------------------------------------------------------
# lib/widgets/common_widgets.dart  (APPEND -- existing PrimaryButton/
# SecondaryButton/AppTextField/SectionCard/ConsentCheckboxTile/ErrorRetryView
# left 100% intact; only Sarah's non-colliding widgets are added)
# ----------------------------------------------------------------------------
cat << 'EOF' >> lib/widgets/common_widgets.dart

// ============================================================================
// --- New decorative widgets from Sarah's UI pass (additive, no collisions) --
// ============================================================================

/// Slow, continuous two-color wave gradient background.
class AnimatedWavyBackground extends StatefulWidget {
  final Widget child;
  const AnimatedWavyBackground({super.key, required this.child});

  @override
  State<AnimatedWavyBackground> createState() => _AnimatedWavyBackgroundState();
}

class _AnimatedWavyBackgroundState extends State<AnimatedWavyBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorB = isDark ? const Color(0xFF17263D) : Colors.white;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        final begin = Alignment(-1 + 2 * t, -1 + 1.4 * t);
        final end = Alignment(1 - 1.4 * t, 1 - 2 * t);
        return Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: begin, end: end, colors: [c.background, colorB, c.background]),
              ),
            ),
            Positioned(
              top: 60 + 30 * t,
              right: -70 + 50 * t,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [c.primary.withOpacity(isDark ? 0.32 : 0.16), Colors.transparent]),
                ),
              ),
            ),
            Positioned(
              bottom: -40 - 20 * t,
              left: -50 + 30 * t,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [c.primaryDark.withOpacity(isDark ? 0.22 : 0.08), Colors.transparent]),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    );
  }
}

/// Light, continuous up/down wave motion for a child (used on buttons/icons).
class WaveMotion extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double amplitude;
  const WaveMotion({super.key, required this.child, this.duration = const Duration(seconds: 2), this.amplitude = 4});

  @override
  State<WaveMotion> createState() => _WaveMotionState();
}

class _WaveMotionState extends State<WaveMotion> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final dy = (Curves.easeInOut.transform(_c.value) - 0.5) * 2 * widget.amplitude;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
    );
  }
}

/// Fade + slight upward slide entrance, optionally delayed (staggered lists).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
  }
}
EOF
echo "    appended AnimatedWavyBackground/WaveMotion/FadeSlideIn to lib/widgets/common_widgets.dart"

# Add the theme import needed by the new widgets above (context.colors)
if ! grep -q "core/app_settings.dart" lib/widgets/common_widgets.dart; then
  sed -i.bak "1a import '../core/app_settings.dart';" lib/widgets/common_widgets.dart
  rm -f lib/widgets/common_widgets.dart.bak
fi

# ----------------------------------------------------------------------------
# lib/screens/settings_screen.dart  (NEW)
# ----------------------------------------------------------------------------
cat << 'EOF' > lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import '../core/app_settings.dart';
import '../core/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'edit_profile_screen.dart';
import 'quick_login_screen.dart';

/// Local device preferences: dark mode, language, text size, quick-login
/// setup, edit-profile entry point. No FastAPI calls originate here directly
/// -- it delegates to EditProfileScreen (real Supabase update) and
/// QuickLoginScreen (local PIN gate on the existing Supabase session).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScope(builder: (context) {
      final c = context.colors;
      return Scaffold(
        appBar: AppBar(title: Text(tr('settings'))),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('settings_personal_section'), style: AppText.label(context)),
              const SizedBox(height: 10),
              SectionCard(
                child: _ActionTile(
                  icon: Icons.edit_outlined,
                  label: tr('edit_personal_data'),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                  },
                ),
              ),
              const SizedBox(height: 26),
              Text(tr('appearance'), style: AppText.label(context)),
              const SizedBox(height: 10),
              SectionCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(color: c.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.dark_mode_outlined, color: c.primaryDark, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Text(tr('dark_mode'), style: AppText.label(context))),
                        Switch(value: appSettings.isDark, onChanged: (v) => appSettings.toggleDarkMode(v)),
                      ],
                    ),
                    Divider(height: 30, color: c.border),
                    Text(tr('language'), style: AppText.body(context)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ChoicePill(label: tr('arabic'), selected: appSettings.isArabic, onTap: () => appSettings.setLanguage('ar')),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ChoicePill(label: tr('english'), selected: !appSettings.isArabic, onTap: () => appSettings.setLanguage('en')),
                        ),
                      ],
                    ),
                    Divider(height: 30, color: c.border),
                    Text(tr('text_size'), style: AppText.body(context)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _ChoicePill(label: tr('size_small'), selected: appSettings.textScale == 0.9, onTap: () => appSettings.setTextScale(0.9))),
                        const SizedBox(width: 8),
                        Expanded(child: _ChoicePill(label: tr('size_medium'), selected: appSettings.textScale == 1.0, onTap: () => appSettings.setTextScale(1.0))),
                        const SizedBox(width: 8),
                        Expanded(child: _ChoicePill(label: tr('size_large'), selected: appSettings.textScale == 1.15, onTap: () => appSettings.setTextScale(1.15))),
                        const SizedBox(width: 8),
                        Expanded(child: _ChoicePill(label: tr('size_xlarge'), selected: appSettings.textScale == 1.3, onTap: () => appSettings.setTextScale(1.3))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(tr('security_section'), style: AppText.label(context)),
              const SizedBox(height: 10),
              SectionCard(
                child: _ActionTile(
                  icon: Icons.pin_outlined,
                  label: tr('create_quick_code_tile'),
                  onTap: () {
                    Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const QuickLoginScreen(mode: QuickLoginMode.setup)));
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    });
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _ActionTile({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = danger ? c.danger : c.primaryDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: AppText.label(context).copyWith(color: danger ? c.danger : null))),
          Icon(appSettings.isArabic ? Icons.arrow_back_ios_new_rounded : Icons.arrow_forward_ios_rounded,
              size: 14, color: c.textSecondary),
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.primary.withOpacity(0.14) : c.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? c.primary : c.border, width: selected ? 1.4 : 1),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? c.primaryDark : c.textSecondary)),
      ),
    );
  }
}
EOF
echo "    wrote lib/screens/settings_screen.dart"

# ----------------------------------------------------------------------------
# lib/screens/edit_profile_screen.dart  (NEW -- REAL Supabase integration,
# not mocked: reads/writes auth.currentUser.userMetadata exactly like the
# existing ProfileScreen reads it.)
# ----------------------------------------------------------------------------
cat << 'EOF' > lib/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_settings.dart';
import '../core/strings.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

/// Edits the same `user_metadata` fields the existing ProfileScreen reads
/// (`first_name`, `last_name`, `phone`) via Supabase's client-side
/// `auth.updateUser`. There is no dedicated `PATCH /profile` endpoint on the
/// FastAPI backend today (only GET-path profile reads via ProfileRepository),
/// so this intentionally goes through Supabase auth metadata -- the same
/// source of truth ProfileScreen already uses -- rather than fabricating a
/// backend call that doesn't exist.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController nameController;
  late final TextEditingController emailController;
  late final TextEditingController phoneController;
  bool isLoading = false;
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    final user = AuthService().currentUser;
    final metadata = user?.userMetadata ?? {};
    final fullName = [metadata['first_name'], metadata['last_name']]
        .where((e) => e != null && (e as String).isNotEmpty)
        .join(' ');
    nameController = TextEditingController(text: fullName);
    emailController = TextEditingController(text: user?.email ?? '');
    phoneController = TextEditingController(text: (metadata['phone'] as String?) ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      isLoading = true;
      errorMsg = null;
    });
    try {
      final parts = nameController.text.trim().split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first : '';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'first_name': firstName,
            'last_name': lastName,
            'phone': phoneController.text.trim(),
          },
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('saved_success'))));
      Navigator.pop(context);
    } on AuthException catch (e) {
      setState(() => errorMsg = e.message);
    } catch (e) {
      setState(() => errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(builder: (context) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('edit_personal_data'))),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(controller: nameController, label: tr('name'), icon: Icons.badge_outlined),
                const SizedBox(height: 14),
                AppTextField(
                    controller: emailController, label: tr('email'), icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 14),
                AppTextField(
                    controller: phoneController, label: tr('phone'), icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
                if (errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 26),
                PrimaryButton(text: tr('save_changes'), isLoading: isLoading, onPressed: _save),
              ],
            ),
          ),
        ),
      );
    });
  }
}
EOF
echo "    wrote lib/screens/edit_profile_screen.dart"

# ----------------------------------------------------------------------------
# lib/screens/quick_login_screen.dart  (NEW -- REAL local PIN gate backed by
# shared_preferences, layered on top of the existing, already-persisted
# Supabase session. Not a second auth system: it never bypasses AuthGate's
# `Supabase.instance.client.auth.currentSession` check.)
# ----------------------------------------------------------------------------
cat << 'EOF' > lib/screens/quick_login_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_settings.dart';
import '../core/strings.dart';
import '../theme/app_theme.dart';
import 'main_navigation_screen.dart';

const String _kQuickLoginCodeKey = 'athar_quick_login_code';

enum QuickLoginMode { setup, login }

/// Local device-convenience PIN gate. Setup mode persists a 5-digit code via
/// SharedPreferences; login mode checks the entered code against it. This
/// never re-authenticates against Supabase or the backend -- it's strictly a
/// faster re-entry path on top of the Supabase session that AuthGate
/// (main.dart) already found valid before routing here.
class QuickLoginScreen extends StatefulWidget {
  final QuickLoginMode mode;
  const QuickLoginScreen({super.key, this.mode = QuickLoginMode.login});

  @override
  State<QuickLoginScreen> createState() => _QuickLoginScreenState();
}

class _QuickLoginScreenState extends State<QuickLoginScreen> {
  static const int codeLength = 5;

  String code = '';
  String? firstEntry;
  bool isConfirmStep = false;
  String? errorMsg;
  bool isLoading = false;

  void _onDigit(String d) {
    if (code.length >= codeLength || isLoading) return;
    setState(() {
      code += d;
      errorMsg = null;
    });
    if (code.length == codeLength) {
      Future.delayed(const Duration(milliseconds: 150), _handleComplete);
    }
  }

  void _onBackspace() {
    if (code.isEmpty || isLoading) return;
    setState(() => code = code.substring(0, code.length - 1));
  }

  Future<void> _handleComplete() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    if (widget.mode == QuickLoginMode.login) {
      setState(() => isLoading = true);
      final storedCode = prefs.getString(_kQuickLoginCodeKey);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      if (storedCode != null && storedCode == code) {
        Navigator.pushAndRemoveUntil(
            context, MaterialPageRoute(builder: (_) => const MainNavigationScreen()), (r) => false);
      } else {
        setState(() {
          isLoading = false;
          errorMsg = tr('codes_dont_match');
          code = '';
        });
      }
    } else {
      if (!isConfirmStep) {
        setState(() {
          firstEntry = code;
          code = '';
          isConfirmStep = true;
        });
      } else {
        if (code == firstEntry) {
          setState(() => isLoading = true);
          await prefs.setString(_kQuickLoginCodeKey, code);
          if (!mounted) return;
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('quick_login_created'))));
          Navigator.pop(context);
        } else {
          setState(() {
            errorMsg = tr('codes_dont_match');
            code = '';
            isConfirmStep = false;
            firstEntry = null;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(builder: (context) {
      final c = context.colors;
      final title = widget.mode == QuickLoginMode.login ? tr('quick_login_title') : tr('create_quick_login_title');
      final subtitle = widget.mode == QuickLoginMode.login
          ? tr('quick_login_subtitle')
          : (isConfirmStep ? tr('confirm_code_subtitle') : tr('create_code_subtitle'));

      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Icon(Icons.lock_clock_rounded, size: 48, color: c.primary),
                const SizedBox(height: 16),
                Text(subtitle, textAlign: TextAlign.center, style: AppText.body(context)),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(codeLength, (i) {
                    final filled = i < code.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? c.primary : Colors.transparent,
                        border: Border.all(color: filled ? c.primary : c.border, width: 1.6),
                      ),
                    );
                  }),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 14),
                  Text(errorMsg!, style: TextStyle(color: c.danger, fontSize: 13)),
                ],
                const Spacer(),
                if (isLoading)
                  CircularProgressIndicator(color: c.primary)
                else
                  _NumberPad(onDigit: _onDigit, onBackspace: _onBackspace),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _NumberPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  const _NumberPad({required this.onDigit, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'back'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key == '') return const SizedBox(width: 64, height: 64);
              if (key == 'back') {
                return _PadKey(child: const Icon(Icons.backspace_outlined), onTap: onBackspace);
              }
              return _PadKey(
                  child: Text(key, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  onTap: () => onDigit(key));
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _PadKey extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PadKey({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(36),
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface, border: Border.all(color: c.border)),
        child: IconTheme(
          data: IconThemeData(color: c.textPrimary),
          child: DefaultTextStyle(style: TextStyle(color: c.textPrimary), child: child),
        ),
      ),
    );
  }
}
EOF
echo "    wrote lib/screens/quick_login_screen.dart"

# ----------------------------------------------------------------------------
# lib/screens/profile_screen.dart  (PATCHED -- one addition: a settings icon
# in the AppBar routing to SettingsScreen. Supabase/AuthService logic below
# is byte-for-byte identical to your working file.)
# ----------------------------------------------------------------------------
cat << 'EOF' > lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import 'welcome_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final metadata = user?.userMetadata ?? {};
    final fullName = [metadata['first_name'], metadata['last_name']]
        .where((e) => e != null && (e as String).isNotEmpty)
        .join(' ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('البيانات الشخصية'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryDark,
                    boxShadow: [BoxShadow(color: AppColors.primaryDark.withOpacity(0.2), blurRadius: 16, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.person, size: 46, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SectionCard(
              child: Column(
                children: [
                  _InfoTile(icon: Icons.badge_outlined, label: 'الاسم', value: fullName.isEmpty ? '—' : fullName),
                  const Divider(height: 26, color: AppColors.border),
                  _InfoTile(icon: Icons.email_outlined, label: 'البريد الإلكتروني', value: user?.email ?? '—'),
                  const Divider(height: 26, color: AppColors.border),
                  _InfoTile(icon: Icons.phone_outlined, label: 'رقم الجوال', value: (metadata['phone'] as String?)?.isNotEmpty == true ? metadata['phone'] : '—'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SecondaryButton(
              text: 'تسجيل الخروج',
              onPressed: () async {
                await AuthService().signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const WelcomeScreen()), (route) => false);
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: AppColors.primaryLight.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primaryDark, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.body),
              const SizedBox(height: 2),
              Text(value, style: AppTextStyles.label),
            ],
          ),
        ),
      ],
    );
  }
}
EOF
echo "    patched lib/screens/profile_screen.dart (added settings nav icon)"

# ----------------------------------------------------------------------------
# lib/main.dart  (PATCHED -- Supabase.initialize + AuthGate kept identical;
# appSettings wiring added around MaterialApp)
# ----------------------------------------------------------------------------
cat << 'EOF' > lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env.dart';
import 'core/app_settings.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_navigation_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  runApp(const AtharApp());
}

class AtharApp extends StatefulWidget {
  const AtharApp({super.key});

  @override
  State<AtharApp> createState() => _AtharAppState();
}

class _AtharAppState extends State<AtharApp> {
  @override
  void initState() {
    super.initState();
    appSettings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    appSettings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'أثَر',
      theme: buildAppTheme(),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: appSettings.themeMode,
      locale: appSettings.locale,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(appSettings.textScale)),
          child: Directionality(
            textDirection: appSettings.isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        );
      },
      routes: {
        '/': (context) => const AuthGate(),
      },
      home: const AuthGate(),
    );
  }
}

/// Routes to the dashboard if a Supabase session already exists (e.g. app
/// relaunch with a persisted session), otherwise to the welcome/auth flow.
/// Unchanged from the working version -- QuickLoginScreen sits ON TOP of
/// this, it never replaces this check.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return session != null ? const MainNavigationScreen() : const WelcomeScreen();
  }
}
EOF
echo "    patched lib/main.dart"

echo "==> Fetching packages"
flutter pub get

echo ""
echo "Done. New/changed files:"
echo "  pubspec.yaml                          (+ shared_preferences)"
echo "  lib/core/app_settings.dart             NEW"
echo "  lib/core/strings.dart                  NEW"
echo "  lib/theme/app_theme.dart                + dark-mode API (appended)"
echo "  lib/widgets/common_widgets.dart          + 3 new widgets (appended)"
echo "  lib/screens/settings_screen.dart       NEW"
echo "  lib/screens/edit_profile_screen.dart   NEW"
echo "  lib/screens/quick_login_screen.dart    NEW"
echo "  lib/screens/profile_screen.dart         patched (settings icon only)"
echo "  lib/main.dart                           patched (appSettings wiring)"