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
