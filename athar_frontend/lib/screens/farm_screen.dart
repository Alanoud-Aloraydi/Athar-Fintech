import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

class FarmScreen extends StatefulWidget {
  final String userId;
  const FarmScreen({super.key, required this.userId});

  @override
  State<FarmScreen> createState() => _FarmScreenState();
}

class _FarmScreenState extends State<FarmScreen> {
  final _api = ApiService();
  late Future<OasisState> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getOasisState(widget.userId);
  }

  void _refresh() => setState(() => _future = _api.getOasisState(widget.userId));

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مزرعة أثَر'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<OasisState>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                const SizedBox(height: 80),
                ErrorRetryView(message: 'تعذّر تحميل حالة المزرعة: ${snapshot.error}', onRetry: _refresh),
              ]);
            }

            final oasis = snapshot.data!;
            final env = oasis.environment;

            return ListView(
              padding: const EdgeInsets.all(20),
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
