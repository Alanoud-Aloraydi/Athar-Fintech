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
