"""
Oasis DTOs (Presentation layer).

Defines the API's public contract for `GET /oasis/{user_id}` and
`POST /oasis/{user_id}/simulate`, consumed by the Spline 3D frontend.
Reuses `OasisEnvironment` directly from the Business layer
(Presentation -> Business is an allowed dependency direction), keeping
the environmental-variable shape guaranteed to match what
`GamificationEngine.derive_environment` actually produces.
"""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.business.gamification.models import OasisEnvironment, OasisImpact
from app.presentation.schemas.transactions import TransactionType


class OasisStateDTO(BaseModel):
    """
    Outbound response for `GET /oasis/{user_id}`.

    Combines the user's persisted, cumulative Oasis stats with the
    derived environmental variables the Spline scene renders — a single,
    optimized response so the frontend never needs a second request to
    resolve "how should the scene look right now".
    """

    user_id: UUID
    growth_level: float = Field(
        description="Persisted cumulative Oasis growth stat."
    )
    health_score: float = Field(
        description="Persisted cumulative Oasis health stat (0-100 scale)."
    )
    current_streak_days: int = Field(
        description="Consecutive days with at least one positive (SAVINGS) action."
    )
    longest_streak_days: int = Field(
        description="The user's longest saving streak on record."
    )
    environment: OasisEnvironment = Field(
        description="Dynamic environmental variables for the 3D Spline scene."
    )
    visible_palm_count: int = Field(
        ge=1,
        le=12,
        description=(
            "How many of the 12 named palms in the Spline scene "
            "('Palm_01'..'Palm_12') should currently be visible, derived "
            "from growth_level via GamificationEngine.palms_visible_for. "
            "The frontend should set Palm_01..Palm_{this} visible=true "
            "and the rest visible=false."
        ),
    )


class OasisSimulationRequestDTO(BaseModel):
    """
    Inbound payload for `POST /oasis/{user_id}/simulate`.

    Describes a *hypothetical* transaction — same shape as
    `TransactionCreateDTO` minus `user_id` and `idempotency_key`, since
    nothing here is ever persisted. Used to power the Farm screen's "try
    a transaction" preview: see what a transaction would do to the Oasis
    before actually logging it.
    """

    model_config = ConfigDict(populate_by_name=True)

    amount: float = Field(gt=0, description="Hypothetical transaction amount; must be positive")
    description: str = Field(
        min_length=1,
        max_length=500,
        description="Raw merchant/transaction description, used for categorization",
    )
    type_enum: TransactionType = Field(
        alias="type", description='Either "EXPENSE" or "INCOME"'
    )


class OasisSimulationResponseDTO(BaseModel):
    """
    Outbound response for `POST /oasis/{user_id}/simulate`.

    Pure preview: nothing about the request is written to any table, no
    balance changes, no goal rollup, no anomaly check. It runs the exact
    same Categorization + Gamification pipeline as a real transaction and
    reports what *would* happen — including the resulting palm count —
    so the client can render a "before / after" of the Oasis.
    """

    predicted_category: str = Field(
        description="The category the Categorization Engine would assign this description"
    )
    oasis_impact: OasisImpact = Field(
        description="The growth/health deltas this transaction would apply"
    )
    current_growth_level: float
    current_health_score: float
    current_visible_palm_count: int = Field(ge=1, le=12)
    projected_growth_level: float
    projected_health_score: float
    projected_visible_palm_count: int = Field(ge=1, le=12)
    newly_unlocked_palms: int = Field(
        ge=0,
        description="projected_visible_palm_count - current_visible_palm_count, clamped to >= 0",
    )
