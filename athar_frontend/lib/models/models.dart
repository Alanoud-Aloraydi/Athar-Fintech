

import 'package:flutter/material.dart';

/// Mirrors backend `app.business.categorization.models.CategoryEnum` exactly.
/// The backend is the single source of truth for this set — do not add
/// values here without adding them server-side first.
enum AppCategory { groceries, utilities, entertainment, savings, uncategorized }

extension AppCategoryX on AppCategory {
  static AppCategory fromApi(String value) {
    switch (value) {
      case 'GROCERIES':
        return AppCategory.groceries;
      case 'UTILITIES':
        return AppCategory.utilities;
      case 'ENTERTAINMENT':
        return AppCategory.entertainment;
      case 'SAVINGS':
        return AppCategory.savings;
      default:
        return AppCategory.uncategorized;
    }
  }

  String get apiValue {
    switch (this) {
      case AppCategory.groceries:
        return 'GROCERIES';
      case AppCategory.utilities:
        return 'UTILITIES';
      case AppCategory.entertainment:
        return 'ENTERTAINMENT';
      case AppCategory.savings:
        return 'SAVINGS';
      case AppCategory.uncategorized:
        return 'UNCATEGORIZED';
    }
  }

  String get label {
    switch (this) {
      case AppCategory.groceries:
        return 'بقالة وتموين';
      case AppCategory.utilities:
        return 'فواتير وخدمات';
      case AppCategory.entertainment:
        return 'ترفيه';
      case AppCategory.savings:
        return 'ادخار';
      case AppCategory.uncategorized:
        return 'غير مصنّف';
    }
  }

  IconData get icon {
    switch (this) {
      case AppCategory.groceries:
        return Icons.shopping_basket_rounded;
      case AppCategory.utilities:
        return Icons.receipt_long_rounded;
      case AppCategory.entertainment:
        return Icons.local_movies_rounded;
      case AppCategory.savings:
        return Icons.savings_rounded;
      case AppCategory.uncategorized:
        return Icons.help_outline_rounded;
    }
  }
}

double _asDouble(dynamic v) => (v as num).toDouble();

/// Mirrors `CategoryBreakdownDTO`.
class CategoryBreakdown {
  final AppCategory category;
  final double totalAmount;
  final int transactionCount;

  CategoryBreakdown({required this.category, required this.totalAmount, required this.transactionCount});

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) => CategoryBreakdown(
        category: AppCategoryX.fromApi(json['category'] as String),
        totalAmount: _asDouble(json['total_amount']),
        transactionCount: json['transaction_count'] as int,
      );
}

/// Mirrors `GoalProgressDTO` (embedded in DashboardSummaryDTO.active_goal).
class GoalProgress {
  final String goalId;
  final String title;
  final double targetAmount;
  final double savedAmount;
  final double progressRatio;

  GoalProgress({
    required this.goalId,
    required this.title,
    required this.targetAmount,
    required this.savedAmount,
    required this.progressRatio,
  });

  factory GoalProgress.fromJson(Map<String, dynamic> json) => GoalProgress(
        goalId: json['goal_id'] as String,
        title: json['title'] as String,
        targetAmount: _asDouble(json['target_amount']),
        savedAmount: _asDouble(json['saved_amount']),
        progressRatio: _asDouble(json['progress_ratio']),
      );
}

/// Mirrors `SmartInsightsDTO`.
class SmartInsights {
  final double spendingVelocityPerDay;
  final DateTime? projectedGoalCompletionDate;
  final String trajectoryMessage;

  SmartInsights({
    required this.spendingVelocityPerDay,
    required this.projectedGoalCompletionDate,
    required this.trajectoryMessage,
  });

  factory SmartInsights.fromJson(Map<String, dynamic> json) => SmartInsights(
        spendingVelocityPerDay: _asDouble(json['spending_velocity_per_day']),
        projectedGoalCompletionDate: json['projected_goal_completion_date'] != null
            ? DateTime.parse(json['projected_goal_completion_date'] as String)
            : null,
        trajectoryMessage: json['trajectory_message'] as String,
      );
}

/// Mirrors `DashboardSummaryDTO` — the unified GET /analytics/{user_id} payload.
class DashboardSummary {
  final String userId;

  // Two-Ledger balances
  final double currentAccountBalance; // liquid daily-use cash
  final double savingsWalletBalance;  // ring-fenced savings, Oasis-linked
  final double currentMonthIncome;
  final double currentMonthExpenses;
  final double netFlow;

  // Active goal summary
  final GoalProgress? activeGoal;
  final double activeGoalTarget;
  final double activeGoalProgressPct;

  // Spending distribution: Arabic label → percentage
  final Map<String, double> spendingByCategory;

  final double oasisGrowthScore;
  final double oasisHealthScore;
  final SmartInsights insights;

  // Open Banking analytics
  final List<String> anomalies;
  final double trajectoryDeviation;
  final double trajectoryDelayMonths;
  final double spendingVolatility;
  final String nudgeMessage;

  // Liquidity metrics
  final double committedObligations;
  final double safeToSpendToday;
  final int daysToPayday;

  // Dynamic Recommended Savings (DRS)
  final double dynamicRecommendedSavings;

  DashboardSummary({
    required this.userId,
    required this.currentAccountBalance,
    required this.savingsWalletBalance,
    required this.currentMonthIncome,
    required this.currentMonthExpenses,
    required this.netFlow,
    required this.activeGoal,
    this.activeGoalTarget = 0.0,
    this.activeGoalProgressPct = 0.0,
    this.spendingByCategory = const {},
    required this.oasisGrowthScore,
    required this.oasisHealthScore,
    required this.insights,
    this.anomalies = const [],
    this.trajectoryDeviation = 0.0,
    this.trajectoryDelayMonths = 0.0,
    this.spendingVolatility = 0.0,
    this.nudgeMessage = '',
    this.committedObligations = 0.0,
    this.safeToSpendToday = 0.0,
    this.daysToPayday = 0,
    this.dynamicRecommendedSavings = 0.0,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) => DashboardSummary(
        userId: json['user_id'] as String,
        currentAccountBalance: _asDouble(json['current_account_balance']),
        savingsWalletBalance: _asDouble(json['savings_wallet_balance']),
        currentMonthIncome: _asDouble(json['current_month_income']),
        currentMonthExpenses: _asDouble(json['current_month_expenses']),
        netFlow: _asDouble(json['net_flow']),
        activeGoal: json['active_goal'] != null
            ? GoalProgress.fromJson(json['active_goal'] as Map<String, dynamic>)
            : null,
        activeGoalTarget: (json['active_goal_target'] as num?)?.toDouble() ?? 0.0,
        activeGoalProgressPct: (json['active_goal_progress_pct'] as num?)?.toDouble() ?? 0.0,
        spendingByCategory: (json['spending_by_category'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            const {},
        oasisGrowthScore: _asDouble(json['oasis_growth_score']),
        oasisHealthScore: _asDouble(json['oasis_health_score']),
        insights: SmartInsights.fromJson(json['insights'] as Map<String, dynamic>),
        anomalies: (json['anomalies'] as List<dynamic>?)?.cast<String>() ?? const [],
        trajectoryDeviation: (json['trajectory_deviation'] as num?)?.toDouble() ?? 0.0,
        trajectoryDelayMonths: (json['trajectory_delay_months'] as num?)?.toDouble() ?? 0.0,
        spendingVolatility: (json['spending_volatility'] as num?)?.toDouble() ?? 0.0,
        nudgeMessage: (json['nudge_message'] as String?) ?? '',
        committedObligations: (json['committed_obligations'] as num?)?.toDouble() ?? 0.0,
        safeToSpendToday: (json['safe_to_spend_today'] as num?)?.toDouble() ?? 0.0,
        daysToPayday: (json['days_to_payday'] as num?)?.toInt() ?? 0,
        dynamicRecommendedSavings:
            (json['dynamic_recommended_savings'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Mirrors `OpenBankingSyncResponseDTO` — response of POST /transactions/sync_open_banking/{user_id}.
class OpenBankingSyncResult {
  final int syncedCount;
  final int alreadySynced;
  final String message;

  OpenBankingSyncResult({
    required this.syncedCount,
    required this.alreadySynced,
    required this.message,
  });

  factory OpenBankingSyncResult.fromJson(Map<String, dynamic> json) => OpenBankingSyncResult(
        syncedCount: json['synced_count'] as int,
        alreadySynced: json['already_synced'] as int,
        message: json['message'] as String,
      );
}

/// Mirrors `GoalResponseDTO`.
class Goal {
  final String id;
  final String userId;
  final String title;
  final double targetAmount;
  final double savedAmount;
  final AppCategory category;
  final DateTime? deadline;
  final String status;
  final DateTime createdAt;

  Goal({
    required this.id,
    required this.userId,
    required this.title,
    required this.targetAmount,
    required this.savedAmount,
    required this.category,
    required this.deadline,
    required this.status,
    required this.createdAt,
  });

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        title: json['title'] as String,
        targetAmount: _asDouble(json['target_amount']),
        savedAmount: _asDouble(json['saved_amount']),
        category: AppCategoryX.fromApi(json['category'] as String),
        deadline: json['deadline'] != null ? DateTime.parse(json['deadline'] as String) : null,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Mirrors `OasisEnvironment` (Business-layer value object, embedded in OasisStateDTO).
class OasisEnvironment {
  final String weatherCondition; // stormy | cloudy | sunny | radiant
  final String visualAura; // dormant | sprouting | flourishing | luminous
  final double streakMultiplier;
  final String moodMessage;

  OasisEnvironment({
    required this.weatherCondition,
    required this.visualAura,
    required this.streakMultiplier,
    required this.moodMessage,
  });

  factory OasisEnvironment.fromJson(Map<String, dynamic> json) => OasisEnvironment(
        weatherCondition: json['weather_condition'] as String,
        visualAura: json['visual_aura'] as String,
        streakMultiplier: _asDouble(json['streak_multiplier']),
        moodMessage: json['mood_message'] as String,
      );
}

/// Mirrors `OasisStateDTO` — GET /oasis/{user_id}.
class OasisState {
  final String userId;
  final double growthLevel;
  final double healthScore;
  final int currentStreakDays;
  final int longestStreakDays;
  final OasisEnvironment environment;
  final int visiblePalmCount;

  OasisState({
    required this.userId,
    required this.growthLevel,
    required this.healthScore,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.environment,
    required this.visiblePalmCount,
  });

  factory OasisState.fromJson(Map<String, dynamic> json) => OasisState(
        userId: json['user_id'] as String,
        growthLevel: _asDouble(json['growth_level']),
        healthScore: _asDouble(json['health_score']),
        currentStreakDays: json['current_streak_days'] as int,
        longestStreakDays: json['longest_streak_days'] as int,
        environment: OasisEnvironment.fromJson(json['environment'] as Map<String, dynamic>),
        // Defensive default for older cached responses during rollout —
        // the backend always sends this field now.
        visiblePalmCount: (json['visible_palm_count'] as int?) ?? 1,
      );
}

/// Mirrors `OasisImpact` (embedded in TransactionResponseDTO and OasisSimulationResponseDTO).
class OasisImpact {
  final double growthDelta;
  final double healthDelta;
  final String triggerReason;

  OasisImpact({required this.growthDelta, required this.healthDelta, required this.triggerReason});

  factory OasisImpact.fromJson(Map<String, dynamic> json) => OasisImpact(
        growthDelta: _asDouble(json['growth_delta']),
        healthDelta: _asDouble(json['health_delta']),
        triggerReason: json['trigger_reason'] as String,
      );
}

/// Mirrors `TransactionResponseDTO` — response of POST /transactions/.
class TransactionResult {
  final String id;
  final String userId;
  final String description;
  final double amount;
  final AppCategory category;
  final String type; // EXPENSE | INCOME
  final DateTime createdAt;
  final OasisImpact oasisImpact;
  final bool isReplay;
  final bool isUnusualSpend;

  TransactionResult({
    required this.id,
    required this.userId,
    required this.description,
    required this.amount,
    required this.category,
    required this.type,
    required this.createdAt,
    required this.oasisImpact,
    required this.isReplay,
    required this.isUnusualSpend,
  });

  factory TransactionResult.fromJson(Map<String, dynamic> json) => TransactionResult(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        description: json['description'] as String,
        amount: _asDouble(json['amount']),
        category: AppCategoryX.fromApi(json['category'] as String),
        type: json['type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        oasisImpact: OasisImpact.fromJson(json['oasis_impact'] as Map<String, dynamic>),
        isReplay: (json['is_replay'] as bool?) ?? false,
        isUnusualSpend: (json['is_unusual_spend'] as bool?) ?? false,
      );
}

/// Mirrors `TransactionHistoryItemDTO` — item shape returned by
/// GET /transactions/{user_id} (the full transaction history list).
class TransactionHistoryItem {
  final String id;
  final String description;
  final double amount;
  final AppCategory category;
  final String type; // EXPENSE | INCOME
  final DateTime createdAt;

  TransactionHistoryItem({
    required this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.type,
    required this.createdAt,
  });

  factory TransactionHistoryItem.fromJson(Map<String, dynamic> json) => TransactionHistoryItem(
        id: json['id'] as String,
        description: json['description'] as String,
        amount: _asDouble(json['amount']),
        category: AppCategoryX.fromApi(json['category'] as String),
        type: json['type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Mirrors `OasisSimulationResponseDTO` — response of POST /oasis/{user_id}/simulate.
///
/// Nothing behind this response is persisted server-side; it's a pure
/// preview used by the Farm screen's "try a transaction" panel.
class OasisSimulationResult {
  final AppCategory predictedCategory;
  final OasisImpact oasisImpact;
  final double currentGrowthLevel;
  final double currentHealthScore;
  final int currentVisiblePalmCount;
  final double projectedGrowthLevel;
  final double projectedHealthScore;
  final int projectedVisiblePalmCount;
  final int newlyUnlockedPalms;

  OasisSimulationResult({
    required this.predictedCategory,
    required this.oasisImpact,
    required this.currentGrowthLevel,
    required this.currentHealthScore,
    required this.currentVisiblePalmCount,
    required this.projectedGrowthLevel,
    required this.projectedHealthScore,
    required this.projectedVisiblePalmCount,
    required this.newlyUnlockedPalms,
  });

  factory OasisSimulationResult.fromJson(Map<String, dynamic> json) => OasisSimulationResult(
        predictedCategory: AppCategoryX.fromApi(json['predicted_category'] as String),
        oasisImpact: OasisImpact.fromJson(json['oasis_impact'] as Map<String, dynamic>),
        currentGrowthLevel: _asDouble(json['current_growth_level']),
        currentHealthScore: _asDouble(json['current_health_score']),
        currentVisiblePalmCount: json['current_visible_palm_count'] as int,
        projectedGrowthLevel: _asDouble(json['projected_growth_level']),
        projectedHealthScore: _asDouble(json['projected_health_score']),
        projectedVisiblePalmCount: json['projected_visible_palm_count'] as int,
        newlyUnlockedPalms: json['newly_unlocked_palms'] as int,
      );
}


