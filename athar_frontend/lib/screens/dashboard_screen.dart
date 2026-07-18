import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

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

  final _currencyFmt =
      NumberFormat.currency(locale: 'ar_SA', symbol: 'ر.س', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _future = _api.getDashboardSummary(widget.userId);
  }

  void _refresh() =>
      setState(() => _future = _api.getDashboardSummary(widget.userId));

  Future<void> _onSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    await Future.delayed(const Duration(seconds: 2)); // secure handshake UX
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
              fmt: _currencyFmt,
            );
          },
        ),
      ),
    );
  }
}

// ─── Body ────────────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  final DashboardSummary data;
  final bool syncing;
  final VoidCallback onSync;
  final NumberFormat fmt;

  const _DashboardBody({
    required this.data,
    required this.syncing,
    required this.onSync,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 48),
      children: [
        // ── Income Header Strip ────────────────────────────────────────
        if (data.totalIncome > 0)
          _IncomeHeaderStrip(
            totalIncome: data.totalIncome,
            totalExpenses: data.totalExpenses,
            fmt: fmt,
          ),
        if (data.totalIncome > 0) const SizedBox(height: 12),

        // ── Safe-to-Spend Card ─────────────────────────────────────────
        if (data.safeToSpendToday > 0 && data.daysToPayday > 0) ...[
          _SafeToSpendCard(
            safeToSpend: data.safeToSpendToday,
            daysToPayday: data.daysToPayday,
            committedObligations: data.committedObligations,
            fmt: fmt,
          ),
          const SizedBox(height: 12),
        ],

        // ── Section 1: رصيد محفظة الإنماء ────────────────────────────
        _WalletSection(
          balance: data.currentBalance,
          income: data.totalIncome,
          expenses: data.totalExpenses,
          fmt: fmt,
          syncing: syncing,
          onSync: onSync,
        ),
        const SizedBox(height: 16),

        // ── Section 2: تحليل مصروفاتك ─────────────────────────────────
        _SpendingAnalysisSection(categories: data.spendingByCategory, fmt: fmt),
        const SizedBox(height: 16),

        // ── Section 3: حالة خطة الادخار ──────────────────────────────
        _SavingsPlanSection(
          deviation: data.trajectoryDeviation,
          delayMonths: data.trajectoryDelayMonths,
          hasGoal: data.activeGoal != null,
          goal: data.activeGoal,
          fmt: fmt,
        ),
        const SizedBox(height: 16),

        // ── Section 4: رادار المصروفات (conditional) ──────────────────
        if (data.anomalies.isNotEmpty) ...[
          _ExpensesRadarSection(
            anomalies: data.anomalies,
            healthScore: data.oasisHealthScore,
          ),
          const SizedBox(height: 16),
        ],

        // ── Section 5: توصية المستشار الذكي ──────────────────────────
        _SmartAdvisorSection(
          message: data.nudgeMessage.isNotEmpty
              ? data.nudgeMessage
              : data.insights.trajectoryMessage,
          volatility: data.spendingVolatility,
          fmt: fmt,
        ),
      ],
    );
  }
}

// ─── Income Header Strip ─────────────────────────────────────────────────────

class _IncomeHeaderStrip extends StatelessWidget {
  final double totalIncome, totalExpenses;
  final NumberFormat fmt;
  const _IncomeHeaderStrip(
      {required this.totalIncome,
      required this.totalExpenses,
      required this.fmt});

  @override
  Widget build(BuildContext context) {
    final spentPct = totalIncome > 0
        ? (totalExpenses / totalIncome * 100).clamp(0.0, 100.0)
        : 0.0;
    final savedPct =
        totalIncome > 0 ? ((totalIncome - totalExpenses) / totalIncome * 100).clamp(0.0, 100.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StripItem(
              label: 'الدخل',
              value: fmt.format(totalIncome),
              color: Colors.white),
          Container(width: 1, height: 28, color: Colors.white30),
          _StripItem(
              label: 'المنصرف',
              value: '${spentPct.toStringAsFixed(0)}٪',
              color: const Color(0xFFFCA5A5)),
          Container(width: 1, height: 28, color: Colors.white30),
          _StripItem(
              label: 'المدخر',
              value: '${savedPct.toStringAsFixed(0)}٪',
              color: const Color(0xFF86EFAC)),
        ],
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StripItem(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 14.5)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Colors.white60, fontSize: 11, height: 1)),
      ],
    );
  }
}

// ─── Safe-to-Spend Card ───────────────────────────────────────────────────────

class _SafeToSpendCard extends StatelessWidget {
  final double safeToSpend, committedObligations;
  final int daysToPayday;
  final NumberFormat fmt;
  const _SafeToSpendCard({
    required this.safeToSpend,
    required this.committedObligations,
    required this.daysToPayday,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFC9A227), Color(0xFFE3B84A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text(
              'المصروف اليومي الآمن',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
            ),
            const Spacer(),
            // Payday countdown chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'الراتب بعد $daysToPayday يوم',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Big amount
          Text(
            fmt.format(safeToSpend),
            style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1),
          ),
          const Text(
            'ريال / اليوم',
            style: TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 12),

          // Tip banner
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'يمكنك صرف ${fmt.format(safeToSpend)} ريال اليوم بأمان حتى يوم الراتب (بعد $daysToPayday يوم)',
              style: const TextStyle(
                  color: Colors.white, fontSize: 12.5, height: 1.55),
            ),
          ),

          // Committed obligations note (if any)
          if (committedObligations > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.lock_outline_rounded,
                  color: Colors.white60, size: 13),
              const SizedBox(width: 5),
              Text(
                'التزامات شهرية (مرابحة): ${fmt.format(committedObligations)} ريال',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

// ─── Section 1: Wallet ───────────────────────────────────────────────────────

class _WalletSection extends StatelessWidget {
  final double balance, income, expenses;
  final NumberFormat fmt;
  final bool syncing;
  final VoidCallback onSync;

  const _WalletSection({
    required this.balance,
    required this.income,
    required this.expenses,
    required this.fmt,
    required this.syncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.account_balance_wallet_rounded,
            title: 'رصيد محفظة الإنماء',
          ),
          const SizedBox(height: 14),
          Text(
            fmt.format(balance),
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text('الرصيد الإجمالي', style: AppTextStyles.small),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _MiniStat(
                label: 'إجمالي الدخل',
                value: fmt.format(income),
                color: AppColors.success,
                icon: Icons.arrow_circle_up_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniStat(
                label: 'إجمالي المصروفات',
                value: fmt.format(expenses),
                color: AppColors.danger,
                icon: Icons.arrow_circle_down_rounded,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          // Sync button inside the wallet card.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: syncing ? null : onSync,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 20),
              label: Text(
                syncing ? 'جارٍ الاتصال بالإنماء...' : 'مزامنة المصرفية المفتوحة 🔄',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section 2: Spending Analysis ────────────────────────────────────────────

class _SpendingAnalysisSection extends StatelessWidget {
  final List<CategoryBreakdown> categories;
  final NumberFormat fmt;

  const _SpendingAnalysisSection(
      {required this.categories, required this.fmt});

  static const Map<String, Color> _catColor = {
    'ENTERTAINMENT': Color(0xFFF59E0B),
    'GROCERIES': Color(0xFF10B981),
    'UTILITIES': Color(0xFF3B82F6),
    'SAVINGS': Color(0xFF065F46),
    'UNCATEGORIZED': Color(0xFF9CA3AF),
  };

  static const Map<String, String> _catLabel = {
    'ENTERTAINMENT': 'طعام وترفيه',
    'GROCERIES': 'بقالة',
    'UTILITIES': 'فواتير',
    'SAVINGS': 'مدخرات',
    'UNCATEGORIZED': 'أخرى',
  };

  @override
  Widget build(BuildContext context) {
    // Show only expense-side categories (exclude pure savings from bar).
    final items =
        categories.where((c) => c.category.name != 'SAVINGS').toList();
    final totalExpenses =
        items.fold(0.0, (s, c) => s + c.totalAmount);

    // Fall back to illustrative mock when no real data yet.
    final hasSeed = items.isNotEmpty && totalExpenses > 0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.donut_small_rounded,
            title: 'تحليل مصروفاتك',
          ),
          const SizedBox(height: 16),

          // ── Segmented bar ───────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 28,
              child: hasSeed
                  ? Row(
                      children: items.map((c) {
                        final frac = (c.totalAmount / totalExpenses)
                            .clamp(0.01, 1.0);
                        final color =
                            _catColor[c.category.name] ??
                                const Color(0xFF9CA3AF);
                        return Flexible(
                          flex: (frac * 1000).round(),
                          child: Container(color: color, height: 28),
                        );
                      }).toList(),
                    )
                  : Row(children: [
                      Flexible(
                          flex: 400,
                          child: Container(
                              color: const Color(0xFFF59E0B), height: 28)),
                      Flexible(
                          flex: 300,
                          child: Container(
                              color: const Color(0xFF3B82F6), height: 28)),
                      Flexible(
                          flex: 300,
                          child: Container(
                              color: const Color(0xFF10B981), height: 28)),
                    ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Legend rows ─────────────────────────────────────────────
          if (hasSeed)
            ...items.map((c) {
              final pct = totalExpenses > 0
                  ? (c.totalAmount / totalExpenses * 100)
                  : 0.0;
              final color =
                  _catColor[c.category.name] ?? const Color(0xFF9CA3AF);
              final label =
                  _catLabel[c.category.name] ?? c.category.label;
              return _LegendRow(
                color: color,
                label: label,
                pct: pct,
                amount: fmt.format(c.totalAmount),
              );
            })
          else ...[
            _LegendRow(
                color: const Color(0xFFF59E0B),
                label: 'طعام وترفيه',
                pct: 40,
                amount: '—'),
            _LegendRow(
                color: const Color(0xFF3B82F6),
                label: 'فواتير',
                pct: 30,
                amount: '—'),
            _LegendRow(
                color: const Color(0xFF10B981),
                label: 'بقالة',
                pct: 30,
                amount: '—'),
            const SizedBox(height: 4),
            const Text(
              'زامن المحفظة لرؤية تحليلك الفعلي',
              style: AppTextStyles.small,
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label, amount;
  final double pct;
  const _LegendRow(
      {required this.color,
      required this.label,
      required this.pct,
      required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: AppTextStyles.label
                        .copyWith(fontWeight: FontWeight.w500))),
            Text(
              '${pct.toStringAsFixed(0)}٪',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 13),
            ),
            if (amount != '—') ...[
              const SizedBox(width: 8),
              Text(amount,
                  style: AppTextStyles.small
                      .copyWith(color: AppColors.textPrimary)),
            ],
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section 3: Savings Plan Status ──────────────────────────────────────────

class _SavingsPlanSection extends StatelessWidget {
  final double deviation, delayMonths;
  final bool hasGoal;
  final GoalProgress? goal;
  final NumberFormat fmt;

  const _SavingsPlanSection({
    required this.deviation,
    required this.delayMonths,
    required this.hasGoal,
    required this.goal,
    required this.fmt,
  });

  String _humanText() {
    if (!hasGoal) {
      return 'حدد خطة ادخار لرؤية توقعات الوصول لهدفك بدقة 🎯';
    }
    if (deviation >= 100) {
      return 'بمعدل ادخارك الحالي، ستصل لهدفك قبل الموعد المحدد 🚀 — '
          'تقدمت بمقدار ${fmt.format(deviation)} ريال عن الخطة';
    }
    if (deviation <= -100 && delayMonths > 0) {
      final months = delayMonths.toStringAsFixed(0);
      return 'أنت متأخر عن الخطة. الخوارزمية تتوقع تأخر هدفك لمدة '
          '$months ${delayMonths == 1 ? 'شهر' : 'أشهر'} '
          'إذا استمريت بهذا المعدل ⚠️';
    }
    return 'مسارك على المسار الصحيح — تابع التزامك بالخطة الشهرية 📈';
  }

  @override
  Widget build(BuildContext context) {
    final ahead = deviation >= 0;
    final statusColor = !hasGoal
        ? AppColors.textSecondary
        : ahead
            ? AppColors.success
            : AppColors.danger;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.savings_rounded,
            title: 'حالة خطة الادخار',
          ),
          const SizedBox(height: 14),

          // Status chip
          if (hasGoal)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ahead
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: statusColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ahead ? 'متقدم على الخطة' : 'متأخر عن الخطة',
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),
          Text(_humanText(), style: AppTextStyles.body),

          // Goal progress bar
          if (goal != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: goal!.progressRatio.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppColors.border,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(goal!.progressRatio * 100).toStringAsFixed(0)}٪',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                      fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${goal!.title} — ${fmt.format(goal!.savedAmount)} من ${fmt.format(goal!.targetAmount)}',
              style: AppTextStyles.small,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Section 4: Expenses Radar ────────────────────────────────────────────────

class _ExpensesRadarSection extends StatelessWidget {
  final List<String> anomalies;
  final double healthScore;

  const _ExpensesRadarSection(
      {required this.anomalies, required this.healthScore});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.danger.withOpacity(0.35), width: 1.5),
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
              child: const Icon(Icons.radar_rounded,
                  color: AppColors.danger, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'رادار المصروفات',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger),
                  ),
                  Text(
                    '${anomalies.length} نمط إنفاق غير طبيعي',
                    style: AppTextStyles.small,
                  ),
                ],
              ),
            ),
            _HealthBadge(score: healthScore),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x22CC4444)),
          const SizedBox(height: 14),
          ...anomalies.map((msg) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            height: 1.1)),
                    Expanded(
                        child: Text(msg,
                            style: const TextStyle(
                                fontSize: 13.5,
                                color: AppColors.textPrimary,
                                height: 1.55))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _HealthBadge extends StatelessWidget {
  final double score;
  const _HealthBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'الواحة ${score.toStringAsFixed(0)}٪',
        style: const TextStyle(
            color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ─── Section 5: Smart Advisor ─────────────────────────────────────────────────

class _SmartAdvisorSection extends StatelessWidget {
  final String message;
  final double volatility;
  final NumberFormat fmt;

  const _SmartAdvisorSection(
      {required this.message, required this.volatility, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.psychology_rounded,
            title: 'توصية المستشار الذكي',
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryDark.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primaryDark.withOpacity(0.15)),
            ),
            child: Text(message,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary, height: 1.65)),
          ),
          if (volatility > 0) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.show_chart_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'تذبذب الإنفاق اليومي: ${fmt.format(volatility)} ر.س',
                style: AppTextStyles.small,
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => SectionCard(child: child);
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppColors.primaryDark, size: 20),
      const SizedBox(width: 8),
      Text(title, style: AppTextStyles.label),
    ]);
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _MiniStat(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.small),
        ],
      ),
    );
  }
}
