import 'package:flutter/material.dart';
import '../core/app_settings.dart';
import '../core/strings.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
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
                    final userId = AuthService().currentUserId;
                    if (userId == null) return;
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => QuickLoginScreen(mode: QuickLoginMode.setup, userId: userId)));
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