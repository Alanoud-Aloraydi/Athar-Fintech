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

  final _currencyFmt = NumberFormat.currency(locale: 'ar_SA', symbol: 'ر.س', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _future = _api.getDashboardSummary(widget.userId);
  }

  void _refresh() => setState(() => _future = _api.getDashboardSummary(widget.userId));

  Future<void> _onSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    // 2-second simulated secure bank handshake.
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
      appBar: AppBar(title: const Text('مركز القيادة المالية'), centerTitle: true),
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

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [

                // ── 1. Sync Banner ────────────────────────────────────
                _SyncBanner(syncing: _syncing, onTap: _onSync),
                const SizedBox(height: 16),

                // ── 2. Anomaly Radar (visible only when anomalies exist)
                if (data.anomalies.isNotEmpty) ...[
                  _AnomalyRadarCard(
                    anomalies: data.anomalies,
                    healthScore: data.oasisHealthScore,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── 3. Wallet Balance ─────────────────────────────────
                _WalletCard(
                  balance: data.currentBalance,
                  income: data.totalIncome,
                  expenses: data.totalExpenses,
                  fmt: _currencyFmt,
                ),
                const SizedBox(height: 16),

                // ── 4. Trajectory Deviation ───────────────────────────
                _TrajectoryCard(
                  deviation: data.trajectoryDeviation,
                  delayMonths: data.trajectoryDelayMonths,
                  hasGoal: data.activeGoal != null,
                  fmt: _currencyFmt,
                ),
                const SizedBox(height: 16),

                // ── 5. Smart Nudge ────────────────────────────────────
                _NudgeCard(
                  nudge: data.nudgeMessage.isNotEmpty
                      ? data.nudgeMessage
                      : data.insights.trajectoryMessage,
                  volatility: data.spendingVolatility,
                  fmt: _currencyFmt,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Sync Banner
// ────────────────────────────────────────────────────────────────────────────

class _SyncBanner extends StatelessWidget {
  final bool syncing;
  final VoidCallback onTap;
  const _SyncBanner({required this.syncing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: syncing ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E40), Color(0xFF2E7D55)],
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: syncing
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.sync_rounded,
                          color: Colors.white, size: 22, key: ValueKey('icon')),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncing
                            ? 'جارٍ الاتصال بمحفظة الإنماء...'
                            : 'مزامنة محفظة الإنماء 🔄',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      if (!syncing)
                        const Text(
                          'اسحب معاملاتك الأخيرة من بنك الإنماء',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (!syncing)
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: Colors.white70, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Anomaly Radar Card
// ────────────────────────────────────────────────────────────────────────────

class _AnomalyRadarCard extends StatelessWidget {
  final List<String> anomalies;
  final double healthScore;
  const _AnomalyRadarCard({required this.anomalies, required this.healthScore});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withOpacity(0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.radar_rounded,
                      color: AppColors.danger, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الرادار المالي',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger)),
                      Text(
                        '${anomalies.length} نمط إنفاق غير طبيعي تم رصده',
                        style: AppTextStyles.small,
                      ),
                    ],
                  ),
                ),
                // Health impact badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'صحة الواحة: ${healthScore.toStringAsFixed(0)}٪',
                    style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0x22CC4444)),
            const SizedBox(height: 14),
            // Anomaly list
            ...anomalies.map((a) => Padding(
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
                        child: Text(a,
                            style: const TextStyle(
                                fontSize: 13.5,
                                color: AppColors.textPrimary,
                                height: 1.5)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Wallet Balance Card
// ────────────────────────────────────────────────────────────────────────────

class _WalletCard extends StatelessWidget {
  final double balance, income, expenses;
  final NumberFormat fmt;
  const _WalletCard(
      {required this.balance,
      required this.income,
      required this.expenses,
      required this.fmt});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.account_balance_wallet_rounded,
                color: AppColors.primaryDark, size: 20),
            SizedBox(width: 8),
            Text('محفظة الإنماء', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 14),
          Text(
            fmt.format(balance),
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark),
          ),
          const SizedBox(height: 2),
          const Text('الرصيد الإجمالي', style: AppTextStyles.small),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _MiniStat(
                    label: 'إجمالي الدخل',
                    value: fmt.format(income),
                    color: AppColors.success,
                    icon: Icons.trending_up_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _MiniStat(
                    label: 'إجمالي المصروفات',
                    value: fmt.format(expenses),
                    color: AppColors.danger,
                    icon: Icons.trending_down_rounded)),
          ]),
        ],
      ),
    );
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

// ────────────────────────────────────────────────────────────────────────────
// Trajectory Deviation Card
// ────────────────────────────────────────────────────────────────────────────

class _TrajectoryCard extends StatelessWidget {
  final double deviation, delayMonths;
  final bool hasGoal;
  final NumberFormat fmt;
  const _TrajectoryCard(
      {required this.deviation,
      required this.delayMonths,
      required this.hasGoal,
      required this.fmt});

  @override
  Widget build(BuildContext context) {
    final ahead = deviation >= 0;
    final color = ahead ? AppColors.success : AppColors.danger;
    final icon =
        ahead ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            const Text('انحراف المسار المالي', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 14),
          if (!hasGoal)
            const Text(
                'أنشئ هدفاً مالياً لمتابعة مسارك بدقة 🎯',
                style: AppTextStyles.body)
          else ...[
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ahead
                        ? 'متقدم بـ ${fmt.format(deviation)} ✅'
                        : 'متأخر بـ ${fmt.format(deviation.abs())}',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                  if (!ahead && delayMonths > 0) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.schedule_rounded,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'تأخر متوقع: ${delayMonths.toStringAsFixed(1)} أشهر',
                        style: AppTextStyles.small,
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Smart Nudge Card
// ────────────────────────────────────────────────────────────────────────────

class _NudgeCard extends StatelessWidget {
  final String nudge;
  final double volatility;
  final NumberFormat fmt;
  const _NudgeCard(
      {required this.nudge, required this.volatility, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final isWarning = nudge.contains('تحذير') ||
        nudge.contains('عطشى') ||
        nudge.contains('مرتفع');
    final iconColor = isWarning ? AppColors.danger : AppColors.gold;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                isWarning
                    ? Icons.warning_amber_rounded
                    : Icons.auto_awesome_rounded,
                color: iconColor,
                size: 20),
            const SizedBox(width: 8),
            const Text('النبضة الذكية', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12)),
            child: Text(nudge, style: AppTextStyles.body),
          ),
          if (volatility > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.show_chart_rounded,
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
