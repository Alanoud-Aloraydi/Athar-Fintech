import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'goal_dialog.dart';
import 'add_transaction_sheet.dart';

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
  final _dateFmt = DateFormat('d MMM yyyy', 'ar');

  @override
  void initState() {
    super.initState();
    _future = _api.getDashboardSummary(widget.userId);
  }

  void _refresh() {
    final f = _api.getDashboardSummary(widget.userId);
    setState(() => _future = f);
  }

  Future<void> _onSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    // Simulate secure bank handshake (2 s visual feedback)
    await Future.delayed(const Duration(seconds: 2));
    try {
      final result = await _api.syncOpenBanking(widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.arabicMessage), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _onAddTransaction() async {
    final result = await showAddTransactionSheet(context, userId: widget.userId);
    if (result == null || !mounted) return;
    final note = result.isUnusualSpend ? ' — ⚠️ مبلغ غير معتاد' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('صُنّفت كـ ${result.category.label}$note\n${result.oasisImpact.triggerReason}')),
    );
    _refresh();
  }

  Future<void> _onCreateGoal() async {
    final goal = await showCreateGoalDialog(context, userId: widget.userId);
    if (goal != null) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة البيانات'), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onAddTransaction,
        icon: const Icon(Icons.add_rounded),
        label: const Text('عملية يدوية'),
        backgroundColor: AppColors.primaryDark,
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
                ErrorRetryView(message: friendlyLoadErrorMessage(snapshot.error), onRetry: _refresh),
              ]);
            }

            final data = snapshot.data!;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
              children: [

                // ── Sync Banner ────────────────────────────────────────
                _SyncBanner(syncing: _syncing, onTap: _onSync),
                const SizedBox(height: 20),

                // ── Card 1: Alinma Wallet Balance ──────────────────────
                _WalletCard(
                  balance: data.currentBalance,
                  income: data.totalIncome,
                  expenses: data.totalExpenses,
                  fmt: _currencyFmt,
                ),
                const SizedBox(height: 16),

                // ── Card 2: Trajectory ─────────────────────────────────
                _TrajectoryCard(
                  deviation: data.trajectoryDeviation,
                  delayMonths: data.trajectoryDelayMonths,
                  hasGoal: data.activeGoal != null,
                  fmt: _currencyFmt,
                ),
                const SizedBox(height: 16),

                // ── Card 3: Smart Nudge ────────────────────────────────
                _NudgeCard(
                  nudge: data.nudgeMessage.isNotEmpty
                      ? data.nudgeMessage
                      : data.insights.trajectoryMessage,
                  volatility: data.spendingVolatility,
                  fmt: _currencyFmt,
                ),
                const SizedBox(height: 20),

                // ── Goal Progress ──────────────────────────────────────
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: const [
                        Icon(Icons.flag_rounded, color: AppColors.gold),
                        SizedBox(width: 8),
                        Text('تقدمك نحو الهدف', style: AppTextStyles.label),
                      ]),
                      const SizedBox(height: 16),
                      if (data.activeGoal != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: data.activeGoal!.progressRatio.clamp(0.0, 1.0),
                            minHeight: 12,
                            backgroundColor: AppColors.border,
                            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${data.activeGoal!.title} — '
                          '${_currencyFmt.format(data.activeGoal!.savedAmount)} من '
                          '${_currencyFmt.format(data.activeGoal!.targetAmount)}',
                          style: AppTextStyles.body,
                        ),
                        if (data.insights.projectedGoalCompletionDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'الموعد المتوقع: ${_dateFmt.format(data.insights.projectedGoalCompletionDate!)}',
                            style: AppTextStyles.small,
                          ),
                        ],
                      ] else ...[
                        const Text('لا يوجد هدف نشط حالياً', style: AppTextStyles.body),
                        const SizedBox(height: 12),
                        SecondaryButton(text: 'إنشاء هدف جديد', onPressed: _onCreateGoal),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Category Breakdown ─────────────────────────────────
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('أقسام الصرف', style: AppTextStyles.label),
                      const SizedBox(height: 14),
                      if (data.spendingByCategory.isEmpty)
                        const Text('لا توجد عمليات مسجّلة بعد — جرّبي مزامنة المحفظة! 🔄', style: AppTextStyles.body)
                      else
                        ...data.spendingByCategory.asMap().entries.map((entry) {
                          final isLast = entry.key == data.spendingByCategory.length - 1;
                          final c = entry.value;
                          return _CategoryRow(
                            icon: c.category.icon,
                            label: '${c.category.label} (${c.transactionCount})',
                            value: _currencyFmt.format(c.totalAmount),
                            isLast: isLast,
                          );
                        }),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Sync Banner ──────────────────────────────────────────────────────────────

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
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.sync_rounded, color: Colors.white, size: 22, key: ValueKey('icon')),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncing ? 'جارٍ الاتصال بمحفظة الإنماء...' : 'مزامنة محفظة الإنماء 🔄',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (!syncing)
                        const Text(
                          'اسحب معاملاتك تلقائياً من بنك الإنماء',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (!syncing)
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Card 1: Wallet Balance ───────────────────────────────────────────────────

class _WalletCard extends StatelessWidget {
  final double balance, income, expenses;
  final NumberFormat fmt;
  const _WalletCard({required this.balance, required this.income, required this.expenses, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.account_balance_wallet_rounded, color: AppColors.primaryDark, size: 20),
            SizedBox(width: 8),
            Text('محفظة الإنماء', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 14),
          Text(
            fmt.format(balance),
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 4),
          const Text('الرصيد الإجمالي', style: AppTextStyles.small),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _MiniStat(label: 'إجمالي الدخل', value: fmt.format(income), color: AppColors.success, icon: Icons.trending_up_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _MiniStat(label: 'إجمالي المصروفات', value: fmt.format(expenses), color: AppColors.danger, icon: Icons.trending_down_rounded)),
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
  const _MiniStat({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.small),
        ],
      ),
    );
  }
}

// ── Card 2: Trajectory ───────────────────────────────────────────────────────

class _TrajectoryCard extends StatelessWidget {
  final double deviation, delayMonths;
  final bool hasGoal;
  final NumberFormat fmt;
  const _TrajectoryCard({required this.deviation, required this.delayMonths, required this.hasGoal, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final ahead = deviation >= 0;
    final color = ahead ? AppColors.success : AppColors.danger;
    final icon = ahead ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            const Text('مسار الهدف المالي', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 14),
          if (!hasGoal) ...[
            const Text('أنشئ هدفاً مالياً لمتابعة مسارك بدقة 🎯', style: AppTextStyles.body),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        ? 'أنت متقدم على الجدول بـ ${fmt.format(deviation)} ✅'
                        : 'أنت متأخر عن هدفك بـ ${fmt.format(deviation.abs())}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
                  ),
                  if (!ahead && delayMonths > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'التأخر المتوقع: ${delayMonths.toStringAsFixed(1)} أشهر تقريباً',
                      style: AppTextStyles.small,
                    ),
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

// ── Card 3: Smart Nudge ──────────────────────────────────────────────────────

class _NudgeCard extends StatelessWidget {
  final String nudge;
  final double volatility;
  final NumberFormat fmt;
  const _NudgeCard({required this.nudge, required this.volatility, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final isWarning = nudge.contains('تحذير') || nudge.contains('عطشى') || nudge.contains('مرتفع');
    final cardColor = isWarning ? AppColors.danger.withOpacity(0.06) : AppColors.primaryLight.withOpacity(0.06);
    final iconColor = isWarning ? AppColors.danger : AppColors.gold;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(isWarning ? Icons.warning_amber_rounded : Icons.auto_awesome_rounded, color: iconColor, size: 20),
            const SizedBox(width: 8),
            const Text('النبضة الذكية', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
            child: Text(nudge, style: AppTextStyles.body),
          ),
          if (volatility > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.show_chart_rounded, size: 14, color: AppColors.textSecondary),
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

// ── Category Row ─────────────────────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final bool isLast;
  const _CategoryRow({required this.icon, required this.label, required this.value, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.primaryLight.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.primaryDark, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTextStyles.label)),
          Text(value, style: AppTextStyles.body),
        ],
      ),
    );
  }
}
