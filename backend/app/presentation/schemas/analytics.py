
"""
Analytics DTOs (Presentation layer).

Define the API's public contract for the spending/Oasis summary endpoints.
Like `schemas/transactions.py`, this reuses `CategoryEnum` directly from
the Business layer (Presentation -> Business is an allowed dependency
direction) rather than duplicating it.
"""

from __future__ import annotations

from datetime import date
from uuid import UUID

from pydantic import BaseModel, Field

from app.business.categorization.models import CategoryEnum


class CategoryBreakdownDTO(BaseModel):
    """Aggregated spend for a single category, part of an analytics summary."""

    category: CategoryEnum
    total_amount: float = Field(description="Sum of transaction amounts in this category")
    transaction_count: int = Field(description="Number of transactions in this category")


class AnalyticsSummaryDTO(BaseModel):
    """
    Outbound response for `GET /analytics/{user_id}/summary`.

    Combines a plain financial rollup (income, expenses, per-category
    breakdown) with the cumulative Oasis growth/health scores implied by
    the user's transaction history, so the Flutter client can render both
    the numbers and the 3D Oasis state from a single response.
    """

    user_id: UUID
    total_income: float = Field(description="Sum of all INCOME-type transaction amounts")
    total_expenses: float = Field(description="Sum of all EXPENSE-type transaction amounts")
    net_flow: float = Field(description="total_income - total_expenses")
    transaction_count: int = Field(description="Total number of transactions considered")
    spending_by_category: list[CategoryBreakdownDTO] = Field(
        description="Per-category breakdown across all transactions"
    )
    oasis_growth_score: float = Field(
        description="The user's persisted cumulative Oasis growth stat"
    )
    oasis_health_score: float = Field(
        description="The user's persisted cumulative Oasis health stat"
    )


class GoalProgressDTO(BaseModel):
    """Compact active-goal progress, embedded in `DashboardSummaryDTO`."""

    goal_id: UUID
    title: str
    target_amount: float
    saved_amount: float
    progress_ratio: float = Field(
        description="saved_amount / target_amount, clamped to [0, 1] in normal operation"
    )


class SmartInsightsDTO(BaseModel):
    """
    Lightweight algorithmic insights block, computed entirely from the
    user's own recent activity (no external data, no third-party model).
    """

    spending_velocity_per_day: float = Field(
        description="Average EXPENSE amount per day over the trailing window"
    )
    projected_goal_completion_date: date | None = Field(
        default=None,
        description=(
            "Predicted date the active goal is reached at the current savings "
            "rate, or null if there's no active goal or the recent savings "
            "rate is negligible."
        ),
    )
    trajectory_message: str = Field(
        description="Short, dynamic, algorithmically-generated status message (warning or praise)"
    )


class DashboardSummaryDTO(BaseModel):
    """
    Outbound response for the unified `GET /analytics/{user_id}` endpoint —
    everything the Flutter dashboard needs in a single call: balance, active
    goal progress, expense breakdown, Oasis scores, Smart Insights, plus the
    Open Banking-derived Trajectory, Volatility, and Liquidity metrics.
    """

    user_id: UUID

    # ── Two-Ledger balances ─────────────────────────────────────────────────
    current_account_balance: float = Field(
        description="Liquid cash for daily use. Simulated: baseline (8,500 SAR) + net monthly cashflow."
    )
    savings_wallet_balance: float = Field(
        description="Ring-fenced savings tied to the Oasis. Simulated: baseline (15,000 SAR) + goal saved_amount."
    )
    current_month_income: float = Field(description="Sum of all INCOME transactions this month")
    current_month_expenses: float = Field(description="Sum of all EXPENSE transactions this month")
    net_flow: float

    # ── Active goal summary ─────────────────────────────────────────────────
    active_goal: GoalProgressDTO | None = Field(
        default=None, description="The user's active Financial Goal, or null if none"
    )
    active_goal_target: float = Field(
        default=0.0, description="Monetary target of the active goal, or 0 if none."
    )
    active_goal_progress_pct: float = Field(
        default=0.0, description="Percentage of the active goal completed (0–100), or 0 if none."
    )

    # ── Spending distribution (Arabic-labelled percentage dict) ─────────────
    spending_by_category: dict[str, float] = Field(
        default_factory=dict,
        description=(
            "Arabic-labelled percentage distribution of current-month EXPENSE transactions. "
            "E.g. {'طعام ومقاهي': 40.0, 'بقالة': 35.0, 'فواتير': 25.0}. "
            "Values sum to ~100. Empty when no EXPENSE transactions exist."
        ),
    )
    oasis_growth_score: float
    oasis_health_score: float
    insights: SmartInsightsDTO

    # --- Open Banking analytics (Trajectory & Volatility) ------------------
    anomalies: list[str] = Field(
        default_factory=list,
        description=(
            "Z-Score anomaly flags generated from the most recent Open Banking sync. "
            "Each entry is a user-facing Arabic string. Empty when no anomalies exist."
        ),
    )
    trajectory_deviation: float = Field(
        default=0.0,
        description=(
            "Expected savings up to today minus actual savings. "
            "Positive = ahead of schedule; negative = behind."
        ),
    )
    trajectory_delay_months: float = Field(
        default=0.0,
        description="Estimated months of delay when trajectory_deviation is negative.",
    )
    spending_volatility: float = Field(
        default=0.0,
        description="Standard deviation of daily EXPENSE totals over the trailing 30-day window.",
    )
    nudge_message: str = Field(
        default="",
        description="Dynamic Arabic nudge generated from volatility and trajectory deviation.",
    )

    # --- Liquidity / Income-Aware metrics ----------------------------------
    committed_obligations: float = Field(
        default=0.0,
        description=(
            "Sum of BNPL / installment EXPENSE transactions (e.g. Tabby). "
            "Sharia-compliant — displayed as 'التزامات' never 'ديون'."
        ),
    )
    safe_to_spend_today: float = Field(
        default=0.0,
        description=(
            "Daily safe amount: (total_income − total_expenses) ÷ days_to_payday. "
            "Zero when days_to_payday is unknown or income is zero."
        ),
    )
    days_to_payday: int = Field(
        default=0,
        description="Calendar days remaining until the 27th of the current (or next) month.",
    )
    dynamic_recommended_savings: float = Field(
        default=0.0,
        description=(
            "Dynamic Recommended Savings (DRS): income − expenses − fixed_obligations − safety_buffer. "
            "The safe surplus available to deposit to savings this month."
        ),
    )
    # ── Explainable AI breakdown (used by the Smart Advisor UI) ─────────────
    avg_income: float = Field(
        default=0.0,
        description="Current month total income — shown verbatim in the advisor explanation.",
    )
    fixed_obligations: float = Field(
        default=0.0,
        description="Fixed committed obligations (Tabby / مرابحة) deducted from the DRS.",
    )
    safety_buffer: float = Field(
        default=0.0,
        description="10% emergency reserve of income excluded from the DRS amount.",
    )


class OpenBankingSyncResponseDTO(BaseModel):
    """Response returned by POST /transactions/sync_open_banking/{user_id}."""

    synced_count: int = Field(description="New transactions persisted this call.")
    already_synced: int = Field(
        description="Transactions skipped — already synced today (idempotency)."
    )
    message: str = Field(description="Arabic user-facing summary message.")
