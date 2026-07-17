"""
Oasis Facade.

`OasisFacade` is the *only* Business-layer class the Presentation layer is
permitted to call for `GET /oasis/{user_id}` and
`POST /oasis/{user_id}/simulate`. It combines the persisted, cumulative
Oasis stats (`OasisRepository`) with the derived environmental
descriptors (`GamificationEngine.derive_environment`) into a single
response — the router never touches `OasisStateRecord` or the repository
directly.
"""

from __future__ import annotations

from uuid import UUID

from app.business.categorization.engine import CategorizationEngine
from app.business.gamification.engine import GamificationEngine
from app.persistence.repositories.oasis_repo import OasisRepository
from app.presentation.schemas.oasis import (
    OasisSimulationRequestDTO,
    OasisSimulationResponseDTO,
    OasisStateDTO,
)

# A brand-new user (no transactions yet, hence no `oasis_states` row) still
# gets a fully-formed response — the Oasis's dormant starting state — rather
# than a null/404, so the Spline scene always has something to render.
_DEFAULT_GROWTH_LEVEL = 0.0
_DEFAULT_HEALTH_SCORE = 100.0
_DEFAULT_STREAK_DAYS = 0


class OasisFacade:
    """<<Facade>> — orchestrates persisted Oasis state, derived environment, and simulation previews."""

    def __init__(
        self,
        oasis_repository: OasisRepository,
        gamification_engine: GamificationEngine,
        categorization_engine: CategorizationEngine,
    ) -> None:
        """
        Args:
            oasis_repository: Repository providing read access to the
                `oasis_states` table.
            gamification_engine: Derives environmental descriptors and
                palm counts from the persisted (or hypothetical) stats.
            categorization_engine: Classifies a hypothetical transaction's
                description for `simulate_transaction_impact` — the same
                engine `TransactionFacade` uses for real transactions, so
                a simulated preview and the real write it previews always
                agree on category.
        """
        self._oasis_repository = oasis_repository
        self._gamification_engine = gamification_engine
        self._categorization_engine = categorization_engine

    def get_oasis_state(self, user_id: str) -> OasisStateDTO:
        """
        Builds the full Oasis state for a user: a single optimized read of
        their persisted running totals (no transaction-history replay),
        plus the environmental variables derived from those totals for the
        3D Spline scene.

        Args:
            user_id: UUID (as string) of the user.

        Returns:
            An `OasisStateDTO` ready to hand straight to the frontend.

        Raises:
            PersistenceError: If the underlying query fails. Allowed to
                propagate to the Presentation layer, which maps it to an
                HTTP response — the Facade does not know about HTTP.
        """
        growth_level, health_score, current_streak_days, longest_streak_days = (
            self._current_stats(user_id)
        )

        environment = self._gamification_engine.derive_environment(
            growth_level=growth_level,
            health_score=health_score,
            current_streak_days=current_streak_days,
        )

        return OasisStateDTO(
            user_id=UUID(user_id),
            growth_level=growth_level,
            health_score=health_score,
            current_streak_days=current_streak_days,
            longest_streak_days=longest_streak_days,
            environment=environment,
            visible_palm_count=self._gamification_engine.palms_visible_for(growth_level),
        )

    def simulate_transaction_impact(
        self, user_id: str, payload: OasisSimulationRequestDTO
    ) -> OasisSimulationResponseDTO:
        """
        Previews what a hypothetical transaction would do to the user's
        Oasis, without writing anything to any table.

        Runs the exact same Categorization + Gamification pipeline
        `TransactionFacade.process_and_store` uses for a real write
        (classify -> evaluate_habit_impact), then projects the resulting
        growth_level/health_score/visible_palm_count on top of the user's
        *current* persisted stats. This is a pure read + pure-function
        computation — no balance change, no goal rollup, no anomaly
        check, no idempotency handling, since none of those matter for a
        "what if" preview.

        Args:
            user_id: UUID (as string) of the user.
            payload: The hypothetical transaction to preview.

        Returns:
            An `OasisSimulationResponseDTO` describing the predicted
            category, the Oasis impact, and a before/after palm count so
            the client can animate "this many new palms would grow".

        Raises:
            PersistenceError: If reading the current Oasis state fails.
        """
        growth_level, health_score, _current_streak_days, _longest = self._current_stats(
            user_id
        )
        current_palm_count = self._gamification_engine.palms_visible_for(growth_level)

        category = self._categorization_engine.classify(payload.description)

        oasis_impact = self._gamification_engine.evaluate_habit_impact(
            transaction_category=category.value,
            transaction_type=payload.type_enum,
            transaction_amount=payload.amount,
        )

        projected_growth_level = growth_level + oasis_impact.growth_delta
        # health_score is a 0-100 scale in normal operation; clamp the
        # projection so a large hypothetical entertainment splurge can't
        # preview a nonsensical negative health score.
        projected_health_score = max(0.0, min(100.0, health_score + oasis_impact.health_delta))
        projected_palm_count = self._gamification_engine.palms_visible_for(
            projected_growth_level
        )

        return OasisSimulationResponseDTO(
            predicted_category=category.value,
            oasis_impact=oasis_impact,
            current_growth_level=growth_level,
            current_health_score=health_score,
            current_visible_palm_count=current_palm_count,
            projected_growth_level=projected_growth_level,
            projected_health_score=projected_health_score,
            projected_visible_palm_count=projected_palm_count,
            newly_unlocked_palms=max(0, projected_palm_count - current_palm_count),
        )

    def _current_stats(self, user_id: str) -> tuple[float, float, int, int]:
        """Reads persisted Oasis stats, falling back to the dormant defaults for a brand-new user."""
        record = self._oasis_repository.get_state(user_id)

        if record is None:
            return (
                _DEFAULT_GROWTH_LEVEL,
                _DEFAULT_HEALTH_SCORE,
                _DEFAULT_STREAK_DAYS,
                _DEFAULT_STREAK_DAYS,
            )

        return (
            record.growth_level,
            record.health_score,
            record.current_streak_days,
            record.longest_streak_days,
        )
