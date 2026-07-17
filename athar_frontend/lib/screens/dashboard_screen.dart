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
  const DashboardScreen({super.key, required this.userId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();
  late Future<DashboardSummary> _future;
  final _currencyFmt = NumberFormat.currency(locale: 'ar_SA', symbol: 'ر.س', decimalDigits: 2);
  final _dateFmt = DateFormat('d MMM yyyy', 'ar');

  @override
  void initState() {
    super.initState();
    _future = _api.getDashboardSummary(widget.userId);
  }

  void _refresh() => setState(() => _future = _api.getDashboardSummary(widget.userId));

  Future<void> _onAddTransaction() async {
    final result = await showAddTransactionSheet(context, userId: widget.userId);
    if (result == null) return;
    if (!mounted) return;

    final categoryNote = 'صُنّفت كـ ${result.category.label}';
    final anomalyNote = result.isUnusualSpend ? ' — ⚠️ مبلغ غير معتاد لهذا التصنيف' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$categoryNote$anomalyNote\n${result.oasisImpact.triggerReason}')),
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
        label: const Text('عملية جديدة'),
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
              padding: const EdgeInsets.all(20),
              children: [
                // --- Balance summary ---
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الرصيد الإجمالي', style: AppTextStyles.label),
                      const SizedBox(height: 8),
                      Text(_currencyFmt.format(data.currentBalance),
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                      const SizedBox(height: 4),
                      Text('صافي التدفق: ${_currencyFmt.format(data.netFlow)}', style: AppTextStyles.body),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- Income / expense stat cards ---
                Row(
                  children: [
                    Expanded(child: _StatCard(title: 'إجمالي المصروفات', value: _currencyFmt.format(data.totalExpenses), icon: Icons.trending_down_rounded, color: AppColors.danger)),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard(title: 'إجمالي الدخل', value: _currencyFmt.format(data.totalIncome), icon: Icons.trending_up_rounded, color: AppColors.success)),
                  ],
                ),
                const SizedBox(height: 16),

                // --- Smart Insights ---
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: const [
                        Icon(Icons.auto_awesome_rounded, color: AppColors.gold),
                        SizedBox(width: 8),
                        Text('رؤى ذكية', style: AppTextStyles.label),
                      ]),
                      const SizedBox(height: 12),
                      Text(data.insights.trajectoryMessage, style: AppTextStyles.body),
                      const SizedBox(height: 8),
                      Text('معدّل الصرف اليومي: ${_currencyFmt.format(data.insights.spendingVelocityPerDay)}', style: AppTextStyles.small),
                      if (data.insights.projectedGoalCompletionDate != null) ...[
                        const SizedBox(height: 4),
                        Text('الموعد المتوقع لتحقيق الهدف: ${_dateFmt.format(data.insights.projectedGoalCompletionDate!)}', style: AppTextStyles.small),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- Goal progress ---
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
                          '${data.activeGoal!.title} — ${_currencyFmt.format(data.activeGoal!.savedAmount)} من ${_currencyFmt.format(data.activeGoal!.targetAmount)}',
                          style: AppTextStyles.body,
                        ),
                      ] else ...[
                        const Text('لا يوجد هدف نشط حالياً', style: AppTextStyles.body),
                        const SizedBox(height: 12),
                        SecondaryButton(text: 'إنشاء هدف جديد', onPressed: _onCreateGoal),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- Category breakdown (from CategoryEnum, backend-derived) ---
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('أقسام الصرف', style: AppTextStyles.label),
                      const SizedBox(height: 14),
                      if (data.spendingByCategory.isEmpty)
                        const Text('لا توجد عمليات مسجّلة بعد', style: AppTextStyles.body)
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
                const SizedBox(height: 90), // clearance for the FAB
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(title, style: AppTextStyles.body),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
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