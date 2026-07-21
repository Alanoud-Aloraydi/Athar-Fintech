import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/oasis_garden_view.dart';
import 'goal_dialog.dart';

class FarmScreen extends StatefulWidget {
  final String userId;

  /// Injectable for widget tests; production callers omit it.
  final ApiService? api;

  const FarmScreen({super.key, required this.userId, this.api});

  @override
  State<FarmScreen> createState() => _FarmScreenState();
}

class _FarmScreenState extends State<FarmScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  late Future<List<Object?>> _dataFuture;

  // DashboardSummary drives the oasis — same data source as the Dashboard
  // tab, ensuring perfect sync (wallet balance, goal progress, health score).
  static final _fmt = NumberFormat('#,##0', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  void _load() {
    _dataFuture = Future.wait<Object?>([
      _api.getDashboardSummary(widget.userId), // ← canonical financial truth
      _api.getOasisState(widget.userId),        // ← streak days only
    ]);
  }

  void _refresh() {
    setState(() {
      _load();
    });
  }

  /// Savings-goal completion ratio (0..1) that drives how many palms grow.
  double _progressFor(DashboardSummary s) => s.activeGoalTarget > 0
      ? (s.savingsWalletBalance / s.activeGoalTarget).clamp(0.0, 1.0)
      : 0.0;

  // ── Goal lifecycle helpers ────────────────────────────────────────────────

  bool _isGoalAchieved(DashboardSummary s) =>
      s.activeGoalProgressPct >= 100 ||
      (s.activeGoalTarget > 0 && s.savingsWalletBalance >= s.activeGoalTarget);

  // ── Goal actions ──────────────────────────────────────────────────────────

  Future<void> _onCreateGoal() async {
    final created = await showCreateGoalDialog(context, userId: widget.userId);
    if (created != null) _refresh();
  }

  /// Completes an achieved goal — moves it to the history register.
  Future<void> _onCompleteGoal(String goalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('إغلاق الهدف وتحويله للسجل؟',
            textAlign: TextAlign.center),
        content: const Text(
          'سيُحفظ هذا الهدف في سجل إنجازاتك ويمكنك بعدها إنشاء هدف ادخاري جديد.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('إغلاق وحفظ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    _callTransition(goalId, 'COMPLETED');
  }

  /// Cancels an active goal and refunds the saved amount to the Current Account.
  Future<void> _onCancelGoal(String goalId, double savedAmount) async {
    final refundText = savedAmount > 0
        ? 'سيتم إعادة ${_fmt.format(savedAmount)} ر.س إلى حسابك الجاري فوراً.'
        : 'لم يتم ادخار أي مبلغ بعد؛ سيُلغى الهدف دون أي تأثير مالي.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('إلغاء الهدف واسترجاع المبلغ؟',
            textAlign: TextAlign.center),
        content: Text(
          '$refundText\n\nستعود الواحة إلى نخلة واحدة بعد الإلغاء.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('إلغاء الهدف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    _callTransition(goalId, 'CANCELLED');
  }

  Future<void> _callTransition(String goalId, String status) async {
    try {
      await _api.transitionGoalStatus(
        userId: widget.userId,
        goalId: goalId,
        newStatus: status,
      );
      _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.arabicMessage),
              backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Section 1 occupies ~45% of the visible screen height.
    final screenHeight = MediaQuery.of(context).size.height;
    final oasisHeight  = screenHeight * 0.43;

    return Scaffold(
      appBar: AppBar(title: const Text('الواحة'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Object?>>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final loaded = snapshot.hasData && !snapshot.hasError;
            final summary = loaded ? snapshot.data![0] as DashboardSummary : null;
            final oasis = loaded ? snapshot.data![1] as OasisState : null;

            // The oasis animates with live data once loaded; while loading it
            // shows a calm, fully-healthy starter oasis (1 palm, clear skies).
            final progress = summary != null ? _progressFor(summary) : 0.0;
            final health = summary?.oasisHealthScore ?? 100.0;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                // ── Section 1: Animated Oasis (Flutter-native) ────────────
                OasisGardenView(
                  height: oasisHeight,
                  progress: progress,
                  health: health,
                ),

                // ── Sections 2–4: FinTech cards ───────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  child: _buildCards(snapshot, summary, oasis),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCards(
    AsyncSnapshot<List<Object?>> snapshot,
    DashboardSummary? summary,
    OasisState? oasis,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (snapshot.hasError || summary == null || oasis == null) {
      return ErrorRetryView(
        message: friendlyLoadErrorMessage(snapshot.error),
        onRetry: _refresh,
      );
    }

    final achieved = _isGoalAchieved(summary);
    final goalId = summary.activeGoal?.goalId.toString();
    final savedAmt = summary.savingsWalletBalance;

    return Column(
      children: [
        // Section 2: الهدف المالي ──────────────────────────
        _GoalCard(
          hasGoal: summary.activeGoal != null,
          isGoalAchieved: achieved,
          goalTitle: summary.activeGoal?.title,
          savedAmount: savedAmt,
          targetAmount: summary.activeGoalTarget,
          fmt: _fmt,
          onComplete:
              (achieved && goalId != null) ? () => _onCompleteGoal(goalId) : null,
          onCancel: (!achieved && goalId != null)
              ? () => _onCancelGoal(goalId, savedAmt)
              : null,
          onCreateGoal: _onCreateGoal,
        ),
        const SizedBox(height: 14),

        // Section 3: حالة الري والحيوية ────────────────────
        _VitalityCard(healthScore: summary.oasisHealthScore),
        const SizedBox(height: 14),

        // Section 4: أيام الالتزام ─────────────────────────
        _CommitmentCard(streakDays: oasis.currentStreakDays),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section 2 — الهدف المالي
// ═══════════════════════════════════════════════════════════════════════════

class _GoalCard extends StatelessWidget {
  final bool hasGoal;
  final bool isGoalAchieved;
  final String? goalTitle;
  final double savedAmount;   // = savings_wallet_balance (canonical)
  final double targetAmount;
  final NumberFormat fmt;
  final VoidCallback? onComplete;  // achieved state → COMPLETED
  final VoidCallback? onCancel;    // active state   → CANCELLED
  final VoidCallback onCreateGoal;

  const _GoalCard({
    required this.hasGoal,
    required this.isGoalAchieved,
    required this.goalTitle,
    required this.savedAmount,
    required this.targetAmount,
    required this.fmt,
    required this.onComplete,
    required this.onCancel,
    required this.onCreateGoal,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(children: [
            Icon(Icons.flag_rounded, color: AppColors.gold, size: 20),
            SizedBox(width: 8),
            Text('الهدف المالي', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 14),

          if (hasGoal) ...[
            // Goal title
            Text(
              goalTitle ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),

            if (isGoalAchieved) ...[
              // ── Goal achieved ────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🏆', style: TextStyle(fontSize: 22)),
                    SizedBox(width: 10),
                    Text(
                      'تم تحقيق الهدف بنجاح!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Gold/Green COMPLETED button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onComplete,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text(
                    'إغلاق الهدف وتحويله للسجل',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ] else ...[
              // ── Goal in progress ────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: (targetAmount > 0 ? savedAmount / targetAmount : 0.0)
                      .clamp(0.0, 1.0),
                  minHeight: 13,
                  backgroundColor: AppColors.border,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primaryDark),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${fmt.format(savedAmount)} من ${fmt.format(targetAmount)} ر.س',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 14),
              // Red CANCELLED button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text(
                    'إلغاء الهدف واسترجاع المبلغ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ] else ...[
            const Text(
              'لا يوجد هدف نشط حالياً — أضف هدفاً ليعكس نمو واحتك تقدّمك نحوه',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              text: 'إضافة هدف ادخاري جديد',
              onPressed: onCreateGoal,
              icon: Icons.add_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section 3 — حالة الري والحيوية
// ═══════════════════════════════════════════════════════════════════════════

class _VitalityCard extends StatelessWidget {
  final double healthScore;
  const _VitalityCard({required this.healthScore});

  @override
  Widget build(BuildContext context) {
    final bool thriving = healthScore >= 80;

    // Spec-exact text
    final String message = thriving
        ? 'واحتك في أزهى حالاتها بفضل التزامك بميزانية الإنماء! 🌟'
        : 'عاجل: واحتك تعطش! التذبذب الأخير في مصروفاتك أثر عليها 🍂';

    final Color accent    = thriving ? AppColors.success : const Color(0xFFD97706);
    final Color textColor = thriving ? AppColors.success : const Color(0xFF92400E);
    final Color bgColor   = thriving
        ? AppColors.success.withValues(alpha: 0.07)
        : const Color(0xFFD97706).withValues(alpha: 0.08);
    final Color borderColor = thriving
        ? AppColors.success.withValues(alpha: 0.25)
        : const Color(0xFFD97706).withValues(alpha: 0.30);
    final IconData icon = thriving
        ? Icons.water_drop_rounded
        : Icons.warning_amber_rounded;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(Icons.water_drop_outlined, color: accent, size: 20),
            const SizedBox(width: 8),
            const Text('حالة الري والحيوية', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 12),

          // Status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Health bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (healthScore / 100).clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'صحة الواحة: ${healthScore.toStringAsFixed(0)}٪',
            style: AppTextStyles.small,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section 4 — أيام الالتزام
// ═══════════════════════════════════════════════════════════════════════════

class _CommitmentCard extends StatelessWidget {
  final int streakDays;
  const _CommitmentCard({required this.streakDays});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          // Flame icon block
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text('🔥', style: TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 16),

          // Text block
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('أيام الالتزام', style: AppTextStyles.label),
                const SizedBox(height: 5),
                Text(
                  'أنت ملتزم بميزانيتك منذ $streakDays يوماً متتالية 🔥',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
