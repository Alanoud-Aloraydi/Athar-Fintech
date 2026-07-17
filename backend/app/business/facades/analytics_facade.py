
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

from collections import defaultdict
from datetime import datetime, timedelta, timezone
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

        return DashboardSummaryDTO(
            user_id=UUID(user_id),
            current_balance=profile.current_balance,
            total_income=total_income,
            total_expenses=total_expenses,
            net_flow=total_income - total_expenses,
            active_goal=goal_progress,
            spending_by_category=breakdown,
            oasis_growth_score=oasis_state.growth_level if oasis_state else 0.0,
            oasis_health_score=oasis_state.health_score if oasis_state else 100.0,
            insights=insights,
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
