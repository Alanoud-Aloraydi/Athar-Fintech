import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import 'welcome_screen.dart';
import 'settings_screen.dart';
import 'quick_login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Future<List<Goal>> _goalsFuture;

  @override
  void initState() {
    super.initState();
    _goalsFuture = ApiService().getGoalHistory(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final metadata = user?.userMetadata ?? {};
    final fullName = [metadata['first_name'], metadata['last_name']]
        .where((e) => e != null && (e as String).isNotEmpty)
        .join(' ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابي'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar ────────────────────────────────────────────────────
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryDark,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withOpacity(0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.person, size: 44, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),

            // ── User info ─────────────────────────────────────────────────
            SectionCard(
              child: Column(
                children: [
                  _InfoTile(
                    icon: Icons.badge_outlined,
                    label: 'الاسم',
                    value: fullName.isEmpty ? '—' : fullName,
                  ),
                  const Divider(height: 26, color: AppColors.border),
                  _InfoTile(
                    icon: Icons.email_outlined,
                    label: 'البريد الإلكتروني',
                    value: user?.email ?? '—',
                  ),
                  const Divider(height: 26, color: AppColors.border),
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'رقم الجوال',
                    value: (metadata['phone'] as String?)?.isNotEmpty == true
                        ? metadata['phone'] as String
                        : '—',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Goals history ─────────────────────────────────────────────
            const Row(
              children: [
                Icon(Icons.history_rounded, color: AppColors.primaryDark, size: 20),
                SizedBox(width: 8),
                Text(
                  'سجل الأهداف الادخارية',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Goal>>(
              future: _goalsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return SectionCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          friendlyLoadErrorMessage(snapshot.error),
                          style: AppTextStyles.small,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }
                final goals = snapshot.data ?? [];
                if (goals.isEmpty) {
                  return SectionCard(
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'لا توجد أهداف مسجّلة حتى الآن 🌱',
                          style: AppTextStyles.small,
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  children: goals
                      .map((g) => _GoalHistoryCard(goal: g))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 28),

            // ── Sign out ──────────────────────────────────────────────────
            SecondaryButton(
              text: 'تسجيل الخروج',
              onPressed: () async {
                await QuickLoginScreen.clearQuickLoginCode(widget.userId);
                await AuthService().signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    (route) => false,
                  );
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

// ─────────────────────────────────────────────────────────────────────────────
// Goal history card
// ─────────────────────────────────────────────────────────────────────────────

class _GoalHistoryCard extends StatelessWidget {
  final Goal goal;
  const _GoalHistoryCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    // Status badge: colour + label
    final (badgeLabel, badgeText, badgeBg) = switch (goal.status) {
      'COMPLETED' => (
          'مكتمل ✓',
          const Color(0xFF92400E),
          const Color(0xFFFFF8E1),
        ),
      'ARCHIVED' => (
          'ملغى',
          const Color(0xFF6B7280),
          const Color(0xFFF3F4F6),
        ),
      _ => (
          'قيد التنفيذ',
          const Color(0xFF065F46),
          const Color(0xFFD1FAE5),
        ),
    };

    final progressPct = goal.targetAmount > 0
        ? (goal.savedAmount / goal.targetAmount * 100).clamp(0.0, 100.0)
        : 0.0;

    final Color barColor = switch (goal.status) {
      'COMPLETED' => const Color(0xFFF59E0B),
      'ARCHIVED'  => const Color(0xFF9CA3AF),
      _           => AppColors.primaryDark,
    };

    final fmt = NumberFormat.currency(
      locale: 'ar_SA',
      symbol: 'ر.س',
      decimalDigits: 0,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + badge
          Row(children: [
            Expanded(
              child: Text(
                goal.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  color: badgeText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Saved / target amounts
          Row(children: [
            Text(
              fmt.format(goal.savedAmount),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
              ),
            ),
            Text(
              ' / ${fmt.format(goal.targetAmount)}',
              style: AppTextStyles.small,
            ),
          ]),
          const SizedBox(height: 8),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressPct / 100,
              minHeight: 7,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),

          // Deadline (optional)
          if (goal.deadline != null) ...[
            const SizedBox(height: 7),
            Row(children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 11, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'الموعد النهائي: ${goal.deadline!.toIso8601String().split('T').first}',
                style: AppTextStyles.small,
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info tile (name / email / phone)
// ─────────────────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
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
    ]);
  }
}
