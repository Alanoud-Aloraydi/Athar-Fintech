"""
Gamification domain models.

`OasisImpact` is the value object returned by `GamificationEngine.evaluate_habit_impact`.
It carries the growth/health deltas that drive the 3D Spline Oasis
visualization, plus a human-readable reason surfaced to the client.

`OasisEnvironment` is the value object returned by
`GamificationEngine.derive_environment`. It's the "wow factor" layer for the
Spline scene — a set of environmental variables computed as a *pure
function* of the persisted, cumulative Oasis stats (`growth_level`,
`health_score`, `current_streak_days`), rather than stored redundantly.
Keeping this derivation as a pure function (no database access, no side
effects) means the "feel" of the Oasis — what health score counts as
"stormy", how many streak days unlock which aura — can be rebalanced for
demo purposes without touching a single persisted row or writing a
migration.
"""
from __future__ import annotations

from pydantic import BaseModel, Field


class OasisImpact(BaseModel):
    """The behavioral impact a single transaction has on the user's Oasis."""

    growth_delta: float = Field(
        description="Change to the Oasis's growth stat; positive nurtures it."
    )
    health_delta: float = Field(
        description="Change to the Oasis's health stat; negative strains it."
    )
    trigger_reason: str = Field(
        description="Human-readable explanation of why this delta was applied."
    )


class OasisEnvironment(BaseModel):
    """
    Dynamic environmental variables for the 3D Spline Oasis scene, derived
    from a user's persisted, cumulative Oasis stats.
    """

    weather_condition: str = Field(
        description=(
            "One of 'stormy', 'cloudy', 'sunny', 'radiant' — driven by "
            "health_score, i.e. how much reckless discretionary spending "
            "has strained the Oasis recently relative to its history."
        )
    )
    visual_aura: str = Field(
        description=(
            "One of 'dormant', 'sprouting', 'flourishing', 'luminous' — "
            "driven by growth_level, i.e. how much saving behavior has "
            "accumulated over the Oasis's lifetime."
        )
    )
    streak_multiplier: float = Field(
        description=(
            "A visual/scoring multiplier derived from current_streak_days "
            "(1.0 at no streak, rising with consecutive saving days, capped "
            "to keep the effect meaningful rather than unbounded)."
        )
    )
    mood_message: str = Field(
        description="Short human-readable status line summarizing the Oasis's current mood."
    )
