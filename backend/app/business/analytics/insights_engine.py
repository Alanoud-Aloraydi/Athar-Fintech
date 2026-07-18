"""
Smart Insights Engine.

Turns a handful of already-aggregated numbers (recent spend, recent savings
rate, active-goal progress, Oasis health) into the "Smart Insights" surfaced
on the unified dashboard: a spending-velocity figure, a predicted
goal-completion date, and a short algorithmic trajectory message. Stateless
and rule-based by design — no ML model, no external call — consistent with
the offline-first/privacy posture of the rest of this backend: every input
here is the user's own data, aggregated locally.

This module lives in the Business layer and is only ever invoked through
`AnalyticsFacade`; it must never be imported directly by the Presentation
layer.
"""

from __future__ import annotations

import statistics as _stats
from collections import defaultdict
from datetime import date, timedelta

from app.presentation.schemas.analytics import SmartInsightsDTO

# A goal projection is only shown if the daily savings rate clears this
# floor — otherwise "reach your goal in 47000 days" is more discouraging
# than useful, so we omit the projection instead.
_MIN_DAILY_SAVINGS_RATE_FOR_PROJECTION = 0.01

# Z-Score threshold: a transaction is flagged as anomalous when its
# per-category Z-Score exceeds this value.
_ANOMALY_Z_THRESHOLD = 2.0

# A category needs at least this many historical data points before
# we trust its baseline statistics enough to run anomaly detection.
_MIN_HISTORICAL_SAMPLES = 2


class InsightsEngine:
    """Stateless rules engine that converts aggregated recent activity into `SmartInsightsDTO`."""

    def generate_insights(
        self,
        recent_expense_total: float,
        recent_income_total: float,
        window_days: int,
        recent_savings_total: float,
        goal_target_amount: float | None,
        goal_saved_amount: float | None,
        oasis_health_score: float,
        current_streak_days: int,
    ) -> SmartInsightsDTO:
        """
        Builds the Smart Insights block.

        Args:
            recent_expense_total: Sum of EXPENSE amounts in the trailing window.
            recent_income_total: Sum of INCOME amounts in the trailing window.
            window_days: Length of the trailing window in days (e.g. 30).
            recent_savings_total: Sum of SAVINGS-category amounts in the
                trailing window — the numerator for the goal-completion
                projection.
            goal_target_amount: The active goal's target, or `None` if the
                user has no active goal.
            goal_saved_amount: The active goal's current `saved_amount`, or
                `None` if the user has no active goal.
            oasis_health_score: The user's persisted cumulative Oasis
                health score (0-100 scale).
            current_streak_days: The user's persisted current saving streak.

        Returns:
            A `SmartInsightsDTO` with a spending-velocity figure, an
            optional projected goal-completion date, and a trajectory
            message.
        """
        window_days = max(window_days, 1)
        spending_velocity = round(recent_expense_total / window_days, 2)
        daily_savings_rate = recent_savings_total / window_days

        projected_completion_date = self._project_goal_completion(
            goal_target_amount=goal_target_amount,
            goal_saved_amount=goal_saved_amount,
            daily_savings_rate=daily_savings_rate,
        )

        trajectory_message = self._build_trajectory_message(
            net_flow=recent_income_total - recent_expense_total,
            oasis_health_score=oasis_health_score,
            current_streak_days=current_streak_days,
            has_projection=projected_completion_date is not None,
        )

        return SmartInsightsDTO(
            spending_velocity_per_day=spending_velocity,
            projected_goal_completion_date=projected_completion_date,
            trajectory_message=trajectory_message,
        )

    @staticmethod
    def _project_goal_completion(
        goal_target_amount: float | None,
        goal_saved_amount: float | None,
        daily_savings_rate: float,
    ) -> date | None:
        if goal_target_amount is None or goal_saved_amount is None:
            return None
        if daily_savings_rate < _MIN_DAILY_SAVINGS_RATE_FOR_PROJECTION:
            return None

        remaining = goal_target_amount - goal_saved_amount
        if remaining <= 0:
            return date.today()

        days_needed = remaining / daily_savings_rate
        return date.today() + timedelta(days=round(days_needed))

    @staticmethod
    def _build_trajectory_message(
        net_flow: float,
        oasis_health_score: float,
        current_streak_days: int,
        has_projection: bool,
    ) -> str:
        if oasis_health_score <= 40:
            return "الإنفاق الترفيهي يضغط على ميزانيتك — حاول تقليصه هذه الفترة 🌪️"
        if net_flow < 0:
            return "إنفاقك يتجاوز دخلك هذه الفترة — راجع المصروفات الأخيرة عن كثب 📉"
        if current_streak_days >= 7:
            return f"سلسلة ادخار قوية {current_streak_days} يوماً — أنت على المسار الصحيح تماماً 🌟"
        if has_projection:
            return "وتيرتك الحالية تضعك في متناول هدفك — واصل هكذا! 🎯"
        return "أوضاعك المالية مستقرة. الادخار المنتظم سيُسرّع تحقيق هدفك 🌱"

    # ------------------------------------------------------------------
    # Z-Score Anomaly Detection
    # ------------------------------------------------------------------

    @staticmethod
    def detect_anomalies(
        all_transactions: list,
        recent_transactions: list,
        oasis_health_score: float,
        total_income: float = 0.0,
    ) -> list[str]:
        """
        Privacy-first, offline Z-Score anomaly detector — leave-one-out variant.

        Algorithm
        ---------
        1. Pool ALL EXPENSE transactions per category from ``all_transactions``
           as ``(id, amount, description)`` tuples.
        2. For each recent EXPENSE transaction, build its **leave-one-out**
           baseline: every other transaction in the same category
           (i.e. all except the one being scored).
        3. Compute Z = (X − μ) / σ against that per-transaction baseline.
        4. Flag where Z > ``_ANOMALY_Z_THRESHOLD`` (default 2.0).

        Leave-one-out is critical for same-day first-sync accuracy: the
        expensive outlier is never allowed to inflate the baseline mean that
        is then used to score itself, so even when all transactions land
        simultaneously a clear spike is detected immediately.

        Categories with fewer than ``_MIN_HISTORICAL_SAMPLES`` *other*
        transactions are skipped — statistics over 1 data-point are
        meaningless.  A near-zero σ (< 0.01) is also skipped to avoid
        degenerate division.

        Args:
            all_transactions:    Every transaction stored for the user —
                                 provides the complete category pool.
            recent_transactions: The recently-synced batch to score.
            oasis_health_score:  Included in the message when health < 80%.

        Returns:
            A (possibly empty) list of human-readable Arabic anomaly strings.
        """
        # Pool all EXPENSE transactions per category.
        cat_pool: dict[str, list[tuple]] = defaultdict(list)
        for txn in all_transactions:
            if txn.type != "EXPENSE":
                continue
            cat_pool[str(txn.category)].append(
                (getattr(txn, "id", None), txn.amount, getattr(txn, "description", ""))
            )

        anomalies: list[str] = []
        for txn in recent_transactions:
            if txn.type != "EXPENSE":
                continue

            cat = str(txn.category)
            txn_id = getattr(txn, "id", None)

            # Leave-one-out: exclude this transaction from its own baseline.
            others = [
                amt
                for tid, amt, _ in cat_pool.get(cat, [])
                if tid != txn_id
            ]

            if len(others) < _MIN_HISTORICAL_SAMPLES:
                continue  # Not enough history to trust the baseline.

            mu = _stats.mean(others)
            sigma = _stats.stdev(others)
            if sigma < 0.01:
                continue  # Near-zero variance → skip to avoid inflated Z.

            z = (txn.amount - mu) / sigma
            if z < _ANOMALY_Z_THRESHOLD:
                continue

            desc = getattr(txn, "description", "")
            anomalies.append(
                f"⚠️ إنفاق غير معتاد في {desc} بقيمة {txn.amount:.0f} ريال. "
                f"(هذا التذبذب له تأثير سلبي على مستوى ارتواء واحتك 🍂)"
            )

        return anomalies

    @staticmethod
    def _category_label_ar(description: str, category: str) -> str:
        """Map a transaction description + category to a natural Arabic label."""
        desc_lower = description.lower()
        if any(w in desc_lower for w in ("coffee", "cafe", "bunn", "قهوة", "كافيه")):
            return "المقاهي"
        if any(w in desc_lower for w in ("restaurant", "albaik", "مطعم", "food")):
            return "المطاعم"
        _MAP = {
            "ENTERTAINMENT": "الترفيه والطعام",
            "GROCERIES": "البقالة",
            "UTILITIES": "الفواتير",
            "SAVINGS": "الادخار",
        }
        return _MAP.get(category.upper(), "هذه الفئة")
