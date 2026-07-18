import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/palm_oasis_viewer.dart';
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

  // Cached after data loads — used to re-sync the scene on controller ready.
  OasisState? _cachedOasis;
  Goal? _cachedGoal;
  PalmOasisController? _oasisController;

  static final _fmt = NumberFormat('#,##0', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  void _load() {
    _dataFuture = Future.wait<Object?>([
      _api.getOasisState(widget.userId),
      _api.getActiveGoal(widget.userId),
    ]);
  }

  void _refresh() {
    setState(() {
      _cachedOasis = null;
      _cachedGoal = null;
      _load();
    });
  }

  // ── 3D scene sync ─────────────────────────────────────────────────────────

  /// Sends growth + health to the Spline scene.
  /// Called whenever either the controller becomes ready OR fresh data arrives.
  void _applyOasisState() {
    final ctrl  = _oasisController;
    final oasis = _cachedOasis;
    if (ctrl == null || !ctrl.isSceneReady || oasis == null) return;

    final goal     = _cachedGoal;
    final progress = (goal != null && goal.targetAmount > 0)
        ? (goal.savedAmount / goal.targetAmount).clamp(0.0, 1.0)
        : 0.0;

    ctrl.updateOasisState(progress: progress, health: oasis.healthScore);
  }

  // ── Goal actions ──────────────────────────────────────────────────────────

  Future<void> _onCreateGoal() async {
    final created = await showCreateGoalDialog(context, userId: widget.userId);
    if (created != null) _refresh();
  }

  Future<void> _onArchiveGoal(Goal goal) async {
    try {
      await _api.transitionGoalStatus(
        userId: widget.userId,
        goalId: goal.id,
        newStatus: 'ARCHIVED',
      );
      _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.arabicMessage), backgroundColor: AppColors.danger),
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
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Section 1: 3D Scene ───────────────────────────────────────
            PalmOasisViewer(
              height: oasisHeight,
              onControllerReady: (ctrl) {
                _oasisController = ctrl;
                _applyOasisState(); // may be no-op if data not yet loaded
              },
            ),

            // ── Sections 2–4: FinTech cards ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: FutureBuilder<List<Object?>>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return ErrorRetryView(
                      message: friendlyLoadErrorMessage(snapshot.error),
                      onRetry: _refresh,
                    );
                  }

                  final oasis = snapshot.data![0] as OasisState;
                  final goal  = snapshot.data![1] as Goal?;

                  // Cache data and re-sync the scene (runs after this build).
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _cachedOasis = oasis;
                    _cachedGoal  = goal;
                    _applyOasisState();
                  });

                  return Column(
                    children: [
                      // Section 2: الهدف المالي ──────────────────────────
                      _GoalCard(
                        goal: goal,
                        fmt: _fmt,
                        onArchive:    goal != null ? () => _onArchiveGoal(goal) : null,
                        onCreateGoal: _onCreateGoal,
                      ),
                      const SizedBox(height: 14),

                      // Section 3: حالة الري والحيوية ────────────────────
                      _VitalityCard(healthScore: oasis.healthScore),
                      const SizedBox(height: 14),

                      // Section 4: أيام الالتزام ─────────────────────────
                      _CommitmentCard(streakDays: oasis.currentStreakDays),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section 2 — الهدف المالي
// ═══════════════════════════════════════════════════════════════════════════

class _GoalCard extends StatelessWidget {
  final Goal? goal;
  final NumberFormat fmt;
  final VoidCallback? onArchive;
  final VoidCallback onCreateGoal;

  const _GoalCard({
    required this.goal,
    required this.fmt,
    required this.onArchive,
    required this.onCreateGoal,
  });

  @override
  Widget build(BuildContext context) {
    final g = goal;
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

          if (g != null) ...[
            // Goal title
            Text(
              g.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (g.targetAmount > 0
                        ? g.savedAmount / g.targetAmount
                        : 0.0)
                    .clamp(0.0, 1.0),
                minHeight: 13,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.primaryDark),
              ),
            ),
            const SizedBox(height: 8),

            // "Title — saved من target ر.س"
            Text(
              '${g.title} — ${fmt.format(g.savedAmount)} من ${fmt.format(g.targetAmount)} ر.س',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 14),

            // Archive action
            SecondaryButton(
              text: 'أرشفة الهدف',
              onPressed: onArchive ?? () {},
            ),
          ] else ...[
            const Text(
              'لا يوجد هدف نشط حالياً — أضف هدفاً ليعكس نمو واحتك تقدّمك نحوه',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              text: 'إضافة هدف جديد',
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
