
"""
Analytics Facade.

`AnalyticsFacade` is the *only* Business-layer class the Presentation
layer is permitted to call for spending/Oasis analytics. It orchestrates
the `TransactionRepository`, `ProfileRepository`, `GoalRepository`, and
`OasisRepository` (all read-only here) plus the `InsightsEngine` to
produce aggregated summaries, so the router never has to fetch raw
transactions, re-run Oasis-impact math, or assemble the dashboard payload
itself.
"""

from __future__ import annotations

import statistics
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from uuid import UUID

from app.business.analytics.insights_engine import InsightsEngine
from app.business.categorization.models import CategoryEnum
from app.core.exceptions import PersistenceError
from app.persistence.models import TransactionRecord
from app.persistence.repositories.goal_repo import GoalRepository
from app.persistence.repositories.oasis_repo import OasisRepository
from app.persistence.repositories.profile_repo import ProfileRepository
from app.persistence.repositories.transaction_repo import TransactionRepository
from app.presentation.schemas.analytics import (
    AnalyticsSummaryDTO,
    CategoryBreakdownDTO,
    DashboardSummaryDTO,
    GoalProgressDTO,
)

_INCOME = "INCOME"
_EXPENSE = "EXPENSE"
_SAVINGS = "SAVINGS"

# Trailing window used for the "Smart Insights" block (spending velocity,
# savings rate, goal-completion projection) on the unified dashboard.
_INSIGHTS_WINDOW_DAYS = 30


class AnalyticsFacade:
    """<<Facade>> — orchestrates spending/Oasis analytics and the unified dashboard summary."""

    def __init__(
        self,
        transaction_repository: TransactionRepository,
        oasis_repository: OasisRepository,
        profile_repository: ProfileRepository,
        goal_repository: GoalRepository,
        insights_engine: InsightsEngine,
    ) -> None:
        """
        Args:
            transaction_repository: Repository providing read access to
                the `transactions` table.
            oasis_repository: Repository providing read access to the
                persisted, cumulative Oasis running totals — used instead
                of replaying transaction history to get growth/health
                scores.
            profile_repository: Repository providing read access to
                `profiles.current_balance`.
            goal_repository: Repository providing read access to the
                user's active Financial Goal.
            insights_engine: Stateless engine that turns aggregated recent
                activity into the "Smart Insights" block.
        """
        self._transaction_repository = transaction_repository
        self._oasis_repository = oasis_repository
        self._profile_repository = profile_repository
        self._goal_repository = goal_repository
        self._insights_engine = insights_engine

    def get_summary(self, user_id: str) -> AnalyticsSummaryDTO:
        """
        Builds the spending/Oasis-scores summary for a user.

        Growth/health scores are read from the persisted `oasis_states`
        row (via `OasisRepository`) rather than recomputed by replaying
        every past transaction through the Gamification Engine — that
        replay used to be the cost of calling this endpoint at all; now
        it's a single indexed row read alongside the transaction fetch
        this endpoint already needed for the category breakdown.

        Args:
            user_id: UUID (as string) of the user to summarize.

        Returns:
            An `AnalyticsSummaryDTO` covering income/expense totals, a
            per-category breakdown, and cumulative Oasis scores.

        Raises:
            PersistenceError: If fetching the user's transactions fails.
                Allowed to propagate to the Presentation layer, which
                maps it to an HTTP response — the Facade does not know
                about HTTP.
        """
        transactions = self._transaction_repository.get_transactions_for_user(user_id)
        oasis_state = self._oasis_repository.get_state(user_id)

        total_income, total_expenses, breakdown = self._summarize_transactions(transactions)

        return AnalyticsSummaryDTO(
            user_id=UUID(user_id),
            total_income=total_income,
            total_expenses=total_expenses,
            net_flow=total_income - total_expenses,
            transaction_count=len(transactions),
            spending_by_category=breakdown,
            oasis_growth_score=oasis_state.growth_level if oasis_state else 0.0,
            oasis_health_score=oasis_state.health_score if oasis_state else 100.0,
        )

    def get_dashboard_summary(self, user_id: str) -> DashboardSummaryDTO:
        """
        Builds the unified `GET /analytics/{user_id}` payload for the
        Flutter dashboard: current balance, active-goal progress, expense
        breakdown, and the Smart Insights block (spending velocity,
        projected goal-completion date, dynamic trajectory message).

        Args:
            user_id: UUID (as string) of the user to summarize.

        Returns:
            A `DashboardSummaryDTO`.

        Raises:
            ProfileNotFoundError: If the user has no `profiles` row.
            PersistenceError: If any underlying query fails. Allowed to
                propagate to the Presentation layer, which maps it to an
                HTTP response — the Facade does not know about HTTP.
        """
        # ensure_profile auto-creates the row with sensible defaults if the
        # Supabase Auth user hasn't had a profile provisioned yet.
        profile = self._profile_repository.ensure_profile(user_id)
        active_goal = self._goal_repository.get_active_goal(user_id)
        oasis_state = self._oasis_repository.get_state(user_id)

        all_transactions = self._transaction_repository.get_transactions_for_user(user_id)
        total_income, total_expenses, breakdown = self._summarize_transactions(all_transactions)

        since = datetime.now(timezone.utc) - timedelta(days=_INSIGHTS_WINDOW_DAYS)
        recent_transactions = self._transaction_repository.get_transactions_since(user_id, since)
        recent_income, recent_expenses, _ = self._summarize_transactions(recent_transactions)
        recent_savings = sum(
            txn.amount for txn in recent_transactions if txn.category == _SAVINGS
        )

        insights = self._insights_engine.generate_insights(
            recent_expense_total=recent_expenses,
            recent_income_total=recent_income,
            window_days=_INSIGHTS_WINDOW_DAYS,
            recent_savings_total=recent_savings,
            goal_target_amount=active_goal.target_amount if active_goal else None,
            goal_saved_amount=active_goal.saved_amount if active_goal else None,
            oasis_health_score=oasis_state.health_score if oasis_state else 100.0,
            current_streak_days=oasis_state.current_streak_days if oasis_state else 0,
        )

        goal_progress = None
        if active_goal is not None:
            goal_progress = GoalProgressDTO(
                goal_id=active_goal.id,
                title=active_goal.title,
                target_amount=active_goal.target_amount,
                saved_amount=active_goal.saved_amount,
                progress_ratio=(
                    round(active_goal.saved_amount / active_goal.target_amount, 4)
                    if active_goal.target_amount > 0
                    else 0.0
                ),
            )

        # Anomaly detection: compare the last 48 h of transactions against
        # the full historical baseline using Z-Score (per-category μ, σ).
        anomaly_since = datetime.now(timezone.utc) - timedelta(hours=48)
        very_recent = self._transaction_repository.get_transactions_since(user_id, anomaly_since)
        current_health = oasis_state.health_score if oasis_state else 100.0
        anomalies = self._insights_engine.detect_anomalies(
            all_transactions, very_recent, current_health
        )

        trajectory_deviation, trajectory_delay_months = self._calculate_trajectory(active_goal)
        spending_volatility = self._calculate_volatility(recent_transactions)
        nudge_message = self._generate_nudge(
            trajectory_deviation, spending_volatility, breakdown
        )

        return DashboardSummaryDTO(
            user_id=UUID(user_id),
            current_balance=profile.current_balance,
            total_income=total_income,
            total_expenses=total_expenses,
            net_flow=total_income - total_expenses,
            active_goal=goal_progress,
            spending_by_category=breakdown,
            oasis_growth_score=oasis_state.growth_level if oasis_state else 0.0,
            oasis_health_score=current_health,
            insights=insights,
            anomalies=anomalies,
            trajectory_deviation=trajectory_deviation,
            trajectory_delay_months=trajectory_delay_months,
            spending_volatility=spending_volatility,
            nudge_message=nudge_message,
        )

    # ------------------------------------------------------------------
    # Open Banking analytics helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _calculate_trajectory(active_goal) -> tuple[float, float]:
        """
        Returns (trajectory_deviation, trajectory_delay_months).

        trajectory_deviation = expected_savings_to_date - actual_saved_amount.
        Positive  → ahead of schedule.
        Negative  → behind schedule.
        """
        if active_goal is None:
            return 0.0, 0.0

        deadline = getattr(active_goal, "deadline", None)
        created_at = getattr(active_goal, "created_at", None)
        if deadline is None or created_at is None:
            return 0.0, 0.0

        # Normalise to plain date objects.
        if isinstance(deadline, datetime):
            deadline = deadline.date()
        if isinstance(created_at, datetime):
            created_at = created_at.date()

        today = date.today()
        total_days = (deadline - created_at).days
        if total_days <= 0:
            return 0.0, 0.0

        elapsed = max(0, (today - created_at).days)
        expected = min(active_goal.target_amount, (elapsed / total_days) * active_goal.target_amount)
        deviation = round(expected - active_goal.saved_amount, 2)

        # Estimate delay months only when behind.
        delay_months = 0.0
        if deviation < 0 and total_days > 0:
            monthly_rate = active_goal.target_amount / max(1, total_days / 30)
            delay_months = round(abs(deviation) / max(1.0, monthly_rate), 1)

        return deviation, delay_months

    @staticmethod
    def _calculate_volatility(transactions: list) -> float:
        """Standard deviation of daily EXPENSE totals (0 if < 2 data points)."""
        daily: dict[date, float] = {}
        for txn in transactions:
            if txn.type != _EXPENSE:
                continue
            d = txn.created_at.date() if isinstance(txn.created_at, datetime) else txn.created_at
            daily[d] = daily.get(d, 0.0) + txn.amount
        values = list(daily.values())
        if len(values) < 2:
            return 0.0
        return round(statistics.stdev(values), 2)

    @staticmethod
    def _generate_nudge(
        deviation: float,
        volatility: float,
        breakdown: list[CategoryBreakdownDTO],
    ) -> str:
        """
        Generates a professional, actionable Arabic advisory message.

        Tone: Smart Advisor — encouraging, specific, never alarmist.
        """
        _CAT_AR = {
            "ENTERTAINMENT": "الطعام والمقاهي",
            "GROCERIES": "البقالة والتموين",
            "UTILITIES": "الفواتير الشهرية",
        }
        # Top non-savings spending category.
        top_cat_ar = ""
        for b in breakdown:
            label = _CAT_AR.get(b.category.value.upper(), "")
            if label:
                top_cat_ar = label
                break

        if deviation < -300:
            return (
                "خطة الادخار تحتاج تدخلاً — حوّل 200 ريال إلى حساب "
                "الإنماء هذا الأسبوع للعودة إلى المسار الصحيح 📊"
            )
        if volatility > 300:
            cat_note = f" {top_cat_ar}" if top_cat_ar else ""
            return (
                f"وفّر من ميزانية{cat_note} هذا الأسبوع، "
                "وحوّل المبلغ مباشرةً للادخار لإنعاش واحتك 🌱"
            )
        if deviation < -100:
            return (
                "خطة ادخارك تحتاج دفعة — حوّل ما وفرته من مصروفات "
                "الطعام إلى حساب الإنماء لتعويض التأخر 💡"
            )
        if deviation > 100:
            return (
                f"أداؤك المالي ممتاز هذا الشهر! تقدمت بـ {deviation:.0f} ريال "
                "عن الخطة — استمر وستحقق هدفك في وقت قياسي 🚀"
            )
        return (
            "وفّر 100 ريال من ميزانية المطاعم هذا الأسبوع، "
            "وحوّلها الآن للادخار لإنعاش واحتك 🌱"
        )

    @staticmethod
    def _summarize_transactions(
        transactions: list[TransactionRecord],
    ) -> tuple[float, float, list[CategoryBreakdownDTO]]:
        """Shared income/expense/category rollup used by both summary endpoints."""
        total_income = 0.0
        total_expenses = 0.0
        category_totals: dict[CategoryEnum, list[float | int]] = defaultdict(
            lambda: [0.0, 0]
        )

        for txn in transactions:
            category = CategoryEnum(txn.category)
            entry = category_totals[category]
            entry[0] += txn.amount
            entry[1] += 1

            if txn.type == _INCOME:
                total_income += txn.amount
            elif txn.type == _EXPENSE:
                total_expenses += txn.amount

        breakdown = [
            CategoryBreakdownDTO(
                category=category, total_amount=total, transaction_count=count
            )
            for category, (total, count) in sorted(
                category_totals.items(), key=lambda item: item[1][0], reverse=True
            )
        ]

        return total_income, total_expenses, breakdown
