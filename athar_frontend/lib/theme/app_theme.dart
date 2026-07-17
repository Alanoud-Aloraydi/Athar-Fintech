import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryDark = Color(0xFF2F6D57);
  static const Color primary = Color(0xFF3F8368);
  static const Color primaryLight = Color(0xFF6BA98C);
  static const Color gold = Color(0xFFC9A227);
  static const Color background = Color(0xFFFAF9F4);
  static const Color card = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1B2B24);
  static const Color textSecondary = Color(0xFF6B7A73);
  static const Color border = Color(0xFFE3DFD2);
  static const Color danger = Color(0xFFC0392B);
  static const Color success = Color(0xFF2E8B57);
}

class AppTextStyles {
  static const String fontFamily = 'Tajawal';

  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: AppColors.primaryDark,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: AppColors.primaryDark,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    color: AppColors.textSecondary,
    height: 1.6,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle small = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12.5,
    color: AppColors.textSecondary,
    height: 1.5,
  );
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primaryDark,
      primary: AppColors.primaryDark,
    ),
    fontFamily: AppTextStyles.fontFamily,
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return Colors.transparent;
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    ),
  );
}

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