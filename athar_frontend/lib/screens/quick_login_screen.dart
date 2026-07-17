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

  /// True if the user has previously set up a quick-login PIN on this
  /// device. AuthGate uses this to decide whether a valid Supabase session
  /// should still be gated behind the PIN screen before reaching the app.
  static Future<bool> hasQuickLoginCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kQuickLoginCodeKey) != null;
  }

  /// Clears the stored PIN. Call this on full sign-out -- the PIN is a
  /// device-local shortcut for whichever account is currently signed in;
  /// leaving it behind after logout would let it silently unlock a
  /// *different* account's session on the same device the next time
  /// someone signs in (since the code isn't scoped per user).
  static Future<void> clearQuickLoginCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kQuickLoginCodeKey);
  }

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