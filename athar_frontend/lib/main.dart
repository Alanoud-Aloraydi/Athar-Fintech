import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env.dart';
import 'core/app_settings.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/quick_login_screen.dart';

/// Whether Supabase initialised successfully.
/// False when credentials are missing (e.g. running on Replit without secrets).
bool _supabaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
      _supabaseReady = true;
    } catch (e) {
      // Credentials supplied but invalid — app will show error screen.
      debugPrint('Supabase init failed: $e');
    }
  }

  // ignore: avoid_print
  print('Supabase initialized: $_supabaseReady');

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
    // Supabase credentials not configured — show a setup prompt instead of
    // crashing. Set SUPABASE_URL and SUPABASE_ANON_KEY as Replit Secrets.
    if (!_supabaseReady) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🌴', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 20),
                const Text(
                  'أَثَر — Athar',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Backend is running ✓\nAdd your Supabase credentials to enable auth & data.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Required Replit Secrets:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('• SUPABASE_URL', style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
                      Text('• SUPABASE_ANON_KEY', style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
                      Text('• SUPABASE_SERVICE_KEY', style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
                      Text('• SUPABASE_JWT_SECRET', style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return const WelcomeScreen();

    final userId = session.user.id;

    return FutureBuilder<bool>(
      // Scoped to this specific account -- see quick_login_screen.dart for
      // why the PIN must never be checked/shown for a different userId.
      future: QuickLoginScreen.hasQuickLoginCode(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data!
            ? QuickLoginScreen(mode: QuickLoginMode.login, userId: userId)
            : const MainNavigationScreen();
      },
    );
  }
}