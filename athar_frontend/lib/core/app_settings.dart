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
