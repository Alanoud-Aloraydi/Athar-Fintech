"""
Oasis DTOs (Presentation layer).

Defines the API's public contract for `GET /oasis/{user_id}`, consumed by
the Spline 3D frontend. Reuses `OasisEnvironment` directly from the
Business layer (Presentation → Business is an allowed dependency
direction), keeping the environmental-variable shape guaranteed to match
what `GamificationEngine.derive_environment` actually produces.
"""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, Field

from app.business.gamification.models import OasisEnvironment


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
