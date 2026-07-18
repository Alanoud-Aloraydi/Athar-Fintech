import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'goal_dialog.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class DashboardScreen extends StatefulWidget {
  final String userId;
  final ApiService? api;

  const DashboardScreen({super.key, required this.userId, this.api});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  late Future<DashboardSummary> _future;
  bool _syncing = false;

  final _fmt = NumberFormat.currency(locale: 'ar_SA', symbol: 'ر.س', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _future = _api.getDashboardSummary(widget.userId);
  }

  void _refresh() => setState(() => _future = _api.getDashboardSummary(widget.userId));

  Future<void> _onSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    await Future.delayed(const Duration(seconds: 2));
    try {
      final result = await _api.syncOpenBanking(widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.message),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
      ));
      _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.arabicMessage),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المستشار المالي الذكي'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<DashboardSummary>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                ErrorRetryView(
                  message: friendlyLoadErrorMessage(snapshot.error),
                  onRetry: _refresh,
                ),
              ]);
            }
            final data = snapshot.data!;
            return _DashboardBody(
              data: data,
              syncing: _syncing,
              onSync: _onSync,
              onRefresh: _refresh,
              userId: widget.userId,
              fmt: _fmt,
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BODY
// ═══════════════════════════════════════════════════════════════════════════

class _DashboardBody extends StatelessWidget {
  final DashboardSummary data;
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onRefresh;
  final String userId;
  final NumberFormat fmt;

  const _DashboardBody({
    required this.data,
    required this.syncing,
    required this.onSync,
    required this.onRefresh,
    required this.userId,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        // ── Section 1: الحساب الجاري ────────────────────────────────────
        _CurrentAccountSection(
          balance: data.currentAccountBalance,
          monthlyIncome: data.currentMonthIncome,
          monthlyExpenses: data.currentMonthExpenses,
          syncing: syncing,
          onSync: onSync,
          fmt: fmt,
        ),
        const SizedBox(height: 24),

        // ── Section 2: أين ذهبت أموالك هذا الشهر؟ ─────────────────────
        _SpendingChartSection(
          spendingByCategory: data.spendingByCategory,
          fmt: fmt,
        ),
        const SizedBox(height: 24),

        // ── Section 3: الرادار والمستشار الذكي ─────────────────────────
        _RadarAdvisorSection(
          anomalies: data.anomalies,
          dynamicRecommendedSavings: data.dynamicRecommendedSavings,
          fixedObligations: data.fixedObligations,
          daysToPayday: data.daysToPayday,
          fmt: fmt,
        ),
        const SizedBox(height: 24),

        // ── Section 4: محفظة الادخار والواحة ──────────────────────────
        _SavingsWalletSection(
          savingsWalletBalance: data.savingsWalletBalance,
          activeGoalTarget: data.activeGoalTarget,
          activeGoalProgressPct: data.activeGoalProgressPct,
          activeGoal: data.activeGoal,
          userId: userId,
          onRefresh: onRefresh,
          fmt: fmt,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 1 ─ الحساب الجاري
// ═══════════════════════════════════════════════════════════════════════════

class _CurrentAccountSection extends StatelessWidget {
  final double balance, monthlyIncome, monthlyExpenses;
  final bool syncing;
  final VoidCallback onSync;
  final NumberFormat fmt;

  const _CurrentAccountSection({
    required this.balance,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.syncing,
    required this.onSync,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'الحساب الجاري', icon: Icons.account_balance_rounded),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A5C40), Color(0xFF0D3D29)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withOpacity(0.30),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sub-label
              const Row(children: [
                Icon(Icons.account_balance_wallet_outlined, color: Colors.white54, size: 14),
                SizedBox(width: 6),
                Text(
                  'إجمالي السيولة النقدية (الحسابات المربوطة)',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ]),
              const SizedBox(height: 10),
              // Main balance
              Text(
                fmt.format(balance),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
              const Text(
                'ريال سعودي',
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.8),
              ),
              const SizedBox(height: 18),
              // Mini stats
              Row(children: [
                Expanded(
                  child: _DarkChip(
                    label: 'دخل الشهر',
                    value: fmt.format(monthlyIncome),
                    isPositive: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DarkChip(
                    label: 'مصروف الشهر',
                    value: fmt.format(monthlyExpenses),
                    isPositive: false,
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              // Sync button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: syncing ? null : onSync,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.15),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white.withOpacity(0.07),
                    disabledForegroundColor: Colors.white54,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
                        )
                      : const Icon(Icons.sync_rounded, size: 20),
                  label: Text(
                    syncing ? 'جارٍ الاتصال بالإنماء...' : 'مزامنة البيانات 🔄',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DarkChip extends StatelessWidget {
  final String label, value;
  final bool isPositive;

  const _DarkChip({required this.label, required this.value, required this.isPositive});

  @override
  Widget build(BuildContext context) {
    final accent = isPositive ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: accent,
            size: 14,
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 2 ─ أين ذهبت أموالك هذا الشهر؟
// ═══════════════════════════════════════════════════════════════════════════

class _SpendingChartSection extends StatelessWidget {
  final Map<String, double> spendingByCategory;
  final NumberFormat fmt;

  const _SpendingChartSection({required this.spendingByCategory, required this.fmt});

  static const _palette = [
    Color(0xFFF59E0B), // amber
    Color(0xFF3B82F6), // blue
    Color(0xFF10B981), // emerald
    Color(0xFFEF4444), // red
    Color(0xFF8B5CF6), // purple
    Color(0xFF9CA3AF), // gray
  ];

  @override
  Widget build(BuildContext context) {
    final entries = spendingByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'أين ذهبت أموالك هذا الشهر؟', icon: Icons.bar_chart_rounded),
        const SizedBox(height: 10),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: entries.isEmpty
                ? const _EmptyState(text: 'زامن البيانات لرؤية توزيع مصروفاتك 📊')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stacked colour bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 26,
                          child: Row(
                            children: entries.asMap().entries.map((e) {
                              final color = _palette[e.key % _palette.length];
                              return Flexible(
                                flex: (e.value.value * 10).round().clamp(1, 99999),
                                child: Container(color: color, height: 26),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Legend rows
                      ...entries.asMap().entries.map((e) {
                        final color = _palette[e.key % _palette.length];
                        return _ChartLegendRow(
                          color: color,
                          label: e.value.key,
                          pct: e.value.value,
                        );
                      }),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ChartLegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final double pct;

  const _ChartLegendRow({required this.color, required this.label, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              '${pct.toStringAsFixed(1)}٪',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 3 ─ الرادار والمستشار الذكي
// ═══════════════════════════════════════════════════════════════════════════

class _RadarAdvisorSection extends StatelessWidget {
  final List<String> anomalies;
  final double dynamicRecommendedSavings;
  final double fixedObligations;
  final int daysToPayday;
  final NumberFormat fmt;

  const _RadarAdvisorSection({
    required this.anomalies,
    required this.dynamicRecommendedSavings,
    required this.fixedObligations,
    required this.daysToPayday,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'الرادار والمستشار الذكي',
          icon: Icons.psychology_rounded,
        ),
        const SizedBox(height: 10),

        // Anomaly card (only shown when anomalies exist)
        if (anomalies.isNotEmpty) ...[
          Container(
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.danger.withOpacity(0.30), width: 1.5),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.radar_rounded, color: AppColors.danger, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'رادار المصروفات',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                        Text(
                          '${anomalies.length} نمط إنفاق غير طبيعي',
                          style: AppTextStyles.small,
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0x22CC4444)),
                const SizedBox(height: 12),
                ...anomalies.map((msg) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '• ',
                            style: TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              height: 1.1,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              msg,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppColors.textPrimary,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Smart Advisor + DRS card
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lightbulb_rounded, color: AppColors.primaryDark, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'توصية المستشار الذكي',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                // DRS advisory box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withOpacity(0.20)),
                  ),
                  child: Text(
                    'بناءً على دخلك، وخصم التزاماتك الأساسية '
                    '(${fmt.format(fixedObligations)} ريال) مع ترك هامش للطوارئ، '
                    'يتبقى لك ${fmt.format(dynamicRecommendedSavings)} ريال كفائض آمن '
                    'يمكن تحويله لمحفظة الادخار.',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.65,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (daysToPayday > 0) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 5),
                    Text('الراتب بعد $daysToPayday يوم', style: AppTextStyles.small),
                  ]),
                ],
                const SizedBox(height: 16),
                // Open Alinma CTA
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showOpenBankingDialog(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      side: const BorderSide(color: AppColors.primaryDark, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text(
                      'افتح تطبيق الإنماء للإيداع 🏦',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showOpenBankingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('افتح تطبيق الإنماء 🏦', textAlign: TextAlign.center),
        content: const Text(
          'سيتم تحويلك لتطبيق الإنماء لإتمام عملية الإيداع عبر الخدمات المصرفية المفتوحة.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
            child: const Text('فتح التطبيق'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 4 ─ محفظة الادخار والواحة
// ═══════════════════════════════════════════════════════════════════════════

class _SavingsWalletSection extends StatelessWidget {
  final double savingsWalletBalance;
  final double activeGoalTarget;
  final double activeGoalProgressPct;
  final GoalProgress? activeGoal;
  final String userId;
  final VoidCallback onRefresh;
  final NumberFormat fmt;

  const _SavingsWalletSection({
    required this.savingsWalletBalance,
    required this.activeGoalTarget,
    required this.activeGoalProgressPct,
    required this.activeGoal,
    required this.userId,
    required this.onRefresh,
    required this.fmt,
  });

  bool get _hasActiveGoal => activeGoal != null;
  // Belt-and-suspenders: catch both the pct signal from the backend
  // AND a direct wallet-vs-target comparison so the UI never lies even if
  // a stale cache sends a slightly rounded percentage.
  bool get _isGoalAchieved =>
      activeGoalProgressPct >= 100 ||
      (activeGoalTarget > 0 && savingsWalletBalance >= activeGoalTarget);

  /// Shows confirmation dialog then archives the goal via API and refreshes.
  Future<void> _archiveGoal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('أرشفة الهدف؟', textAlign: TextAlign.center),
        content: const Text(
          'سيُغلق هذا الهدف ويمكنك بعدها إنشاء هدف جديد لنخلتك.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ApiService().transitionGoalStatus(
        userId: userId,
        goalId: activeGoal!.goalId,
        newStatus: 'ARCHIVED',
      );
      onRefresh();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.arabicMessage), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'محفظة الادخار والواحة', icon: Icons.savings_rounded),
        const SizedBox(height: 10),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Savings balance row
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.lock_rounded, color: AppColors.success, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'رصيد محفظة الادخار',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        Text(
                          fmt.format(savingsWalletBalance),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                            height: 1.1,
                          ),
                        ),
                        const Text(
                          'ريال سعودي',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ]),

                // Goal progress / achieved state
                if (_hasActiveGoal && activeGoalTarget > 0) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 14),

                  if (_isGoalAchieved) ...[
                    // ── Goal achieved banner ────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
                      ),
                      child: const Column(
                        children: [
                          Text('🏆', style: TextStyle(fontSize: 34)),
                          SizedBox(height: 6),
                          Text(
                            'تم تحقيق الهدف بنجاح!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'أحسنت! يمكنك الآن البدء بهدف جديد 👏',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // ── In-progress goal ────────────────────────────────────
                    Row(children: [
                      const Icon(Icons.flag_rounded, color: AppColors.primaryDark, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          activeGoal!.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${activeGoalProgressPct.toStringAsFixed(1)}٪',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                          fontSize: 14,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (activeGoalProgressPct / 100).clamp(0.0, 1.0),
                        minHeight: 12,
                        backgroundColor: AppColors.border,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primaryDark),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${fmt.format(activeGoal!.savedAmount)} من ${fmt.format(activeGoalTarget)} ريال',
                      style: AppTextStyles.small,
                    ),
                  ],
                ],

                const SizedBox(height: 20),

                // Smart goal button — 3 states: achieved / in-progress / none
                if (_hasActiveGoal && _isGoalAchieved) ...[
                  // Goal achieved: offer archive + new goal
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _archiveGoal(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.archive_rounded),
                      label: const Text(
                        'أرشفة الهدف والبدء بهدف جديد',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ] else if (_hasActiveGoal) ...[
                  // Goal in-progress: block new goals
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD97706).withOpacity(0.40)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'يجب إكمال أو إلغاء الهدف الحالي لتبدأ هدفاً جديداً لنخلتك.',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // No active goal: allow creating one
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final created = await showCreateGoalDialog(context, userId: userId);
                        if (created != null) onRefresh();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text(
                        'إضافة هدف ادخاري جديد 🎯',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ═══════════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppColors.primaryDark, size: 20),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(text, style: AppTextStyles.small, textAlign: TextAlign.center),
      ),
    );
  }
}
