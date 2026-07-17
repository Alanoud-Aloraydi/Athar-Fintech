
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/palm_oasis_viewer.dart';
import 'goal_dialog.dart';

class FarmScreen extends StatefulWidget {
  final String userId;

  /// Injectable for widget tests; production callers omit it and get the
  /// real [ApiService].
  final ApiService? api;

  const FarmScreen({super.key, required this.userId, this.api});

  @override
  State<FarmScreen> createState() => _FarmScreenState();
}

class _FarmScreenState extends State<FarmScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  late Future<OasisState> _oasisFuture;
  late Future<Goal?> _goalFuture;

  PalmOasisController? _oasisController;
  OasisState? _lastOasis;

  @override
  void initState() {
    super.initState();
    _oasisFuture = _api.getOasisState(widget.userId);
    _goalFuture = _api.getActiveGoal(widget.userId);
  }

  void _refresh() {
    setState(() {
      _oasisFuture = _api.getOasisState(widget.userId);
      _goalFuture = _api.getActiveGoal(widget.userId);
    });
  }

  /// Re-syncs the live 3D scene with the real, persisted palm count.
  /// Called after the initial load and any time we back out of a
  /// simulator preview.
  void _applyRealPalmCount(OasisState oasis) {
    _lastOasis = oasis;
    final controller = _oasisController;
    if (controller != null && controller.isSceneReady) {
      controller.setVisiblePalms(oasis.visiblePalmCount);
    }
  }

  String _weatherLabel(String w) {
    switch (w) {
      case 'stormy':
        return 'عاصفة';
      case 'cloudy':
        return 'غائم';
      case 'sunny':
        return 'مشمس';
      case 'radiant':
        return 'مشرق';
      default:
        return w;
    }
  }

  IconData _weatherIcon(String w) {
    switch (w) {
      case 'stormy':
        return Icons.thunderstorm_rounded;
      case 'cloudy':
        return Icons.cloud_rounded;
      case 'sunny':
        return Icons.wb_sunny_rounded;
      case 'radiant':
        return Icons.wb_twilight_rounded;
      default:
        return Icons.cloud_queue_rounded;
    }
  }

  String _auraLabel(String a) {
    switch (a) {
      case 'dormant':
        return 'خامدة';
      case 'sprouting':
        return 'براعم ناشئة';
      case 'flourishing':
        return 'مزدهرة';
      case 'luminous':
        return 'متألقة';
      default:
        return a;
    }
  }

  Future<void> _onCreateGoal() async {
    final goal = await showCreateGoalDialog(context, userId: widget.userId);
    if (goal != null) _refresh();
  }

  Future<void> _onArchiveGoal(Goal goal) async {
    try {
      await _api.transitionGoalStatus(userId: widget.userId, goalId: goal.id, newStatus: 'ARCHIVED');
      _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.arabicMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مزرعة أثَر'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // --- 3D Palm Oasis scene ---
            PalmOasisViewer(
              onControllerReady: (controller) {
                _oasisController = controller;
                final oasis = _lastOasis;
                if (oasis != null) {
                  // Scene may finish loading after the data already
                  // arrived (or vice versa) -- either order works since
                  // we re-apply here once the controller exists.
                  controller.setVisiblePalms(oasis.visiblePalmCount);
                }
              },
            ),
            const SizedBox(height: 16),

            FutureBuilder<OasisState>(
              future: _oasisFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return ErrorRetryView(message: friendlyLoadErrorMessage(snapshot.error), onRetry: _refresh);
                }

                final oasis = snapshot.data!;
                // Keep the live scene synced every time fresh data lands
                // (e.g. after a pull-to-refresh or committing a real
                // transaction from the simulator below).
                WidgetsBinding.instance.addPostFrameCallback((_) => _applyRealPalmCount(oasis));
                final env = oasis.environment;

                return Column(
                  children: [
                    SectionCard(
                      child: Column(
                        children: [
                          Icon(_weatherIcon(env.weatherCondition), size: 56, color: AppColors.primaryLight),
                          const SizedBox(height: 12),
                          Text(env.moodMessage, textAlign: TextAlign.center, style: AppTextStyles.h2),
                          const SizedBox(height: 6),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              Chip(label: Text('الطقس: ${_weatherLabel(env.weatherCondition)}')),
                              Chip(label: Text('الهالة: ${_auraLabel(env.visualAura)}')),
                              Chip(label: Text('النخيل: ${oasis.visiblePalmCount}/12')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _StatTile(label: 'مستوى النمو', value: oasis.growthLevel.toStringAsFixed(1), icon: Icons.eco_rounded, color: AppColors.success)),
                        const SizedBox(width: 12),
                        Expanded(child: _StatTile(label: 'الصحة العامة', value: '${oasis.healthScore.toStringAsFixed(0)}٪', icon: Icons.favorite_rounded, color: AppColors.danger)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _StatTile(label: 'السلسلة الحالية', value: '${oasis.currentStreakDays} يوم', icon: Icons.local_fire_department_rounded, color: AppColors.gold)),
                        const SizedBox(width: 12),
                        Expanded(child: _StatTile(label: 'أطول سلسلة', value: '${oasis.longestStreakDays} يوم', icon: Icons.emoji_events_rounded, color: AppColors.primaryDark)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      child: Row(
                        children: [
                          const Icon(Icons.bolt_rounded, color: AppColors.gold),
                          const SizedBox(width: 10),
                          Expanded(child: Text('مُضاعِف السلسلة الحالي: ×${env.streakMultiplier.toStringAsFixed(2)}', style: AppTextStyles.label)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            // --- Goal management ---
            FutureBuilder<Goal?>(
              future: _goalFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SectionCard(
                    child: Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
                  );
                }
                if (snapshot.hasError) {
                  // Don't silently pretend "no active goal" when the fetch
                  // failed -- surface the error with a retry, same as the
                  // Oasis section above.
                  return SectionCard(
                    child: ErrorRetryView(
                      message: friendlyLoadErrorMessage(snapshot.error),
                      onRetry: _refresh,
                    ),
                  );
                }
                final goal = snapshot.data;
                return SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: const [
                        Icon(Icons.flag_rounded, color: AppColors.gold),
                        SizedBox(width: 8),
                        Text('هدفك المالي', style: AppTextStyles.label),
                      ]),
                      const SizedBox(height: 14),
                      if (goal != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: (goal.targetAmount <= 0 ? 0.0 : goal.savedAmount / goal.targetAmount).clamp(0.0, 1.0),
                            minHeight: 12,
                            backgroundColor: AppColors.border,
                            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('${goal.title} — ${goal.savedAmount.toStringAsFixed(2)} من ${goal.targetAmount.toStringAsFixed(2)}', style: AppTextStyles.body),
                        const SizedBox(height: 12),
                        SecondaryButton(text: 'أرشفة الهدف', onPressed: () => _onArchiveGoal(goal)),
                      ] else ...[
                        const Text('لا يوجد هدف نشط حالياً — أضف هدفاً ليعكس نمو واحتك تقدّمك نحوه', style: AppTextStyles.body),
                        const SizedBox(height: 12),
                        PrimaryButton(text: 'إضافة هدف جديد', onPressed: _onCreateGoal, icon: Icons.add_rounded),
                      ],
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // --- Transaction simulator ("what if" preview, nothing persisted) ---
            _TransactionSimulatorCard(
              userId: widget.userId,
              api: _api,
              baselineOasis: _lastOasis,
              onPreview: (result) => _oasisController?.setVisiblePalms(result.projectedVisiblePalmCount),
              onResetPreview: () {
                final oasis = _lastOasis;
                if (oasis != null) _applyRealPalmCount(oasis);
              },
              onCommitted: _refresh,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({required this.label, required this.value, required this.icon, required this.color});

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
          Text(label, style: AppTextStyles.body),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// "Try a transaction" panel: lets the user type a hypothetical
/// description/amount/type, calls `POST /oasis/{user_id}/simulate` (no
/// persistence), and shows the predicted category + Oasis impact. While a
/// result is showing, the 3D scene above previews the projected palm
/// count via [onPreview]; [onResetPreview] snaps it back to the real
/// count. The user can then either discard the preview or commit it as a
/// real transaction via [onCommitted].
class _TransactionSimulatorCard extends StatefulWidget {
  final String userId;
  final ApiService api;
  final OasisState? baselineOasis;
  final ValueChanged<OasisSimulationResult> onPreview;
  final VoidCallback onResetPreview;
  final VoidCallback onCommitted;

  const _TransactionSimulatorCard({
    required this.userId,
    required this.api,
    required this.baselineOasis,
    required this.onPreview,
    required this.onResetPreview,
    required this.onCommitted,
  });

  @override
  State<_TransactionSimulatorCard> createState() => _TransactionSimulatorCardState();
}

class _TransactionSimulatorCardState extends State<_TransactionSimulatorCard> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String _type = 'EXPENSE';
  bool _isSimulating = false;
  bool _isCommitting = false;
  OasisSimulationResult? _result;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _onSimulate() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (_descriptionController.text.trim().isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال وصف ومبلغ صحيحين')));
      return;
    }
    setState(() {
      _isSimulating = true;
      _result = null;
    });
    try {
      final result = await widget.api.simulateOasisImpact(
        userId: widget.userId,
        amount: amount,
        description: _descriptionController.text.trim(),
        type: _type,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _isSimulating = false;
      });
      widget.onPreview(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSimulating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.arabicMessage)));
    }
  }

  void _discardPreview() {
    setState(() => _result = null);
    widget.onResetPreview();
  }

  Future<void> _commitTransaction() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null) return;
    setState(() => _isCommitting = true);
    try {
      await widget.api.createTransaction(
        userId: widget.userId,
        amount: amount,
        description: _descriptionController.text.trim(),
        type: _type,
      );
      if (!mounted) return;
      setState(() {
        _isCommitting = false;
        _result = null;
        _descriptionController.clear();
        _amountController.clear();
      });
      widget.onCommitted();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isCommitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.arabicMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.science_rounded, color: AppColors.primaryDark),
            SizedBox(width: 8),
            Text('جرّب معاملة على واحتك', style: AppTextStyles.label),
          ]),
          const SizedBox(height: 4),
          const Text('معاينة فقط — لن تُسجَّل أي عملية إلا إذا اخترت ذلك بعد المعاينة', style: AppTextStyles.small),
          const SizedBox(height: 14),
          AppTextField(controller: _descriptionController, label: 'وصف العملية (مثال: Starbucks)', icon: Icons.edit_note_rounded),
          const SizedBox(height: 12),
          AppTextField(controller: _amountController, label: 'المبلغ', icon: Icons.payments_rounded, keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('مصروف'),
                  selected: _type == 'EXPENSE',
                  onSelected: (_) => setState(() => _type = 'EXPENSE'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Text('دخل'),
                  selected: _type == 'INCOME',
                  onSelected: (_) => setState(() => _type = 'INCOME'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            text: 'شوف تأثيرها على الواحة',
            isLoading: _isSimulating,
            onPressed: _onSimulate,
            icon: Icons.play_arrow_rounded,
          ),
          if (result != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(label: Text('التصنيف المتوقع: ${result.predictedCategory.label}')),
              if (result.newlyUnlockedPalms > 0)
                Chip(
                  label: Text('🌴 +${result.newlyUnlockedPalms} نخلة جديدة!'),
                  backgroundColor: AppColors.success.withOpacity(0.15),
                ),
            ]),
            const SizedBox(height: 10),
            Text(result.oasisImpact.triggerReason, style: AppTextStyles.body),
            const SizedBox(height: 10),
            _ImpactRow(
              label: 'النمو',
              before: result.currentGrowthLevel,
              after: result.projectedGrowthLevel,
            ),
            _ImpactRow(
              label: 'الصحة',
              before: result.currentHealthScore,
              after: result.projectedHealthScore,
            ),
            Text(
              'النخيل الظاهر: ${result.currentVisiblePalmCount} ← ${result.projectedVisiblePalmCount} من 12',
              style: AppTextStyles.small,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: SecondaryButton(text: 'تجاهل المعاينة', onPressed: _discardPreview)),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    text: 'سجّلها فعلياً',
                    isLoading: _isCommitting,
                    onPressed: _commitTransaction,
                    icon: Icons.check_rounded,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  final String label;
  final double before;
  final double after;

  const _ImpactRow({required this.label, required this.before, required this.after});

  @override
  Widget build(BuildContext context) {
    final delta = after - before;
    final deltaColor = delta > 0 ? AppColors.success : (delta < 0 ? AppColors.danger : AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text('$label: ${before.toStringAsFixed(1)} ← ${after.toStringAsFixed(1)}', style: AppTextStyles.body)),
          Text(
            delta == 0 ? 'بدون تغيير' : (delta > 0 ? '+${delta.toStringAsFixed(1)}' : delta.toStringAsFixed(1)),
            style: TextStyle(color: deltaColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
