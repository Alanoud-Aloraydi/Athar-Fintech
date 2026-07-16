"""
Oasis Facade.

`OasisFacade` is the *only* Business-layer class the Presentation layer is
permitted to call for `GET /oasis/{user_id}`. It combines the persisted,
cumulative Oasis stats (`OasisRepository`) with the derived environmental
descriptors (`GamificationEngine.derive_environment`) into a single
response — the router never touches `OasisStateRecord` or the repository
directly.
"""

from __future__ import annotations

from uuid import UUID

from app.business.gamification.engine import GamificationEngine
from app.persistence.repositories.oasis_repo import OasisRepository
from app.presentation.schemas.oasis import OasisStateDTO

# A brand-new user (no transactions yet, hence no `oasis_states` row) still
# gets a fully-formed response — the Oasis's dormant starting state — rather
# than a null/404, so the Spline scene always has something to render.
_DEFAULT_GROWTH_LEVEL = 0.0
_DEFAULT_HEALTH_SCORE = 100.0
_DEFAULT_STREAK_DAYS = 0


class OasisFacade:
    """<<Facade>> — orchestrates persisted Oasis state + derived environment."""

    def __init__(
        self,
        oasis_repository: OasisRepository,
        gamification_engine: GamificationEngine,
    ) -> None:
        """
        Args:
            oasis_repository: Repository providing read access to the
                `oasis_states` table.
            gamification_engine: Derives environmental descriptors from
                the persisted stats.
        """
        self._oasis_repository = oasis_repository
        self._gamification_engine = gamification_engine

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
        record = self._oasis_repository.get_state(user_id)

        if record is None:
            growth_level = _DEFAULT_GROWTH_LEVEL
            health_score = _DEFAULT_HEALTH_SCORE
            current_streak_days = _DEFAULT_STREAK_DAYS
            longest_streak_days = _DEFAULT_STREAK_DAYS
        else:
            growth_level = record.growth_level
            health_score = record.health_score
            current_streak_days = record.current_streak_days
            longest_streak_days = record.longest_streak_days

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
        )
