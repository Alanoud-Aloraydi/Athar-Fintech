"""Persistence-layer database record models."""
from __future__ import annotations
from datetime import date, datetime
from uuid import UUID
from pydantic import BaseModel, ConfigDict

class ProfileRecord(BaseModel):
    """Mirrors the `profiles` table."""
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    full_name: str | None = None
    current_balance: float = 0.0
    created_at: datetime

class GoalRecord(BaseModel):
    """Mirrors the `goals` table."""
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    user_id: UUID
    title: str
    target_amount: float
    saved_amount: float = 0.0
    category: str
    deadline: date | None = None
    status: str
    created_at: datetime
    updated_at: datetime | None = None

class TransactionRecord(BaseModel):
    """Mirrors the `transactions` table."""
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    user_id: UUID
    amount: float
    description: str
    category: str
    type: str
    created_at: datetime
    idempotency_key: str | None = None


class OasisStateRecord(BaseModel):
    """
    Mirrors the `oasis_states` table.

    Holds the *persisted, cumulative* Oasis stats for a user — the running
    totals that `create_transaction_atomic` updates in the same statement as
    the transaction insert (see
    `supabase/migrations/002_oasis_gamification_and_idempotency.sql`), so
    nothing in the Business or Presentation layer ever needs to replay a
    user's full transaction history to answer "what does their Oasis look
    like right now".
    """
    model_config = ConfigDict(from_attributes=True)
    user_id: UUID
    growth_level: float = 0.0
    health_score: float = 100.0
    current_streak_days: int = 0
    longest_streak_days: int = 0
    last_positive_action_date: date | None = None
    updated_at: datetime


class TransactionWriteResult(BaseModel):
    """
    Return shape of the `create_transaction_atomic` RPC.

    Combines the persisted (or, on replay, pre-existing) transaction row
    with the up-to-date Oasis snapshot produced by the *same* atomic
    statement, plus `is_replay` so the Business layer can tell a genuine
    write apart from an idempotent replay without a second query.
    """
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    user_id: UUID
    amount: float
    description: str
    category: str
    type: str
    created_at: datetime
    idempotency_key: str | None = None
    is_replay: bool = False
    oasis_growth_level: float = 0.0
    oasis_health_score: float = 100.0
    oasis_streak_days: int = 0
