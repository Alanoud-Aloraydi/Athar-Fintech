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

from datetime import date, timedelta

from app.presentation.schemas.analytics import SmartInsightsDTO

# A goal projection is only shown if the daily savings rate clears this
# floor — otherwise "reach your goal in 47000 days" is more discouraging
# than useful, so we omit the projection instead.
_MIN_DAILY_SAVINGS_RATE_FOR_PROJECTION = 0.01


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
            return "Discretionary spending has been straining your budget this period — consider dialing it back."
        if net_flow < 0:
            return "You're spending more than you're bringing in this period — worth a closer look at recent expenses."
        if current_streak_days >= 7:
            return f"Strong {current_streak_days}-day saving streak — you're on a great trajectory."
        if has_projection:
            return "Your current pace puts your goal within reach — keep it up."
        return "Your finances are stable this period. Consistent saving will accelerate your goal progress."
