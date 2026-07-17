import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env.dart';
import 'core/app_settings.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/quick_login_screen.dart';

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

/// Routes to:
/// - WelcomeScreen, if there's no Supabase session at all (never signed in,
///   or fully signed out).
/// - QuickLoginScreen (PIN gate), if a Supabase session exists AND the user
///   previously set up a quick-login PIN on this device -- this is the
///   fast re-entry path (e.g. reopening the app after it was backgrounded
///   or closed, session still valid) instead of dropping straight into the
///   app with no local gate at all.
/// - MainNavigationScreen directly, if a session exists but no PIN was ever
///   set up (previous, simpler behavior is preserved for users who never
///   opted into quick login).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const WelcomeScreen();

    return FutureBuilder<bool>(
      future: QuickLoginScreen.hasQuickLoginCode(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data!
            ? const QuickLoginScreen(mode: QuickLoginMode.login)
            : const MainNavigationScreen();
      },
    );
  }
}