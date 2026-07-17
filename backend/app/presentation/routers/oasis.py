"""
Oasis Router (Presentation layer).

Exposes the optimized Oasis-state endpoint consumed by the Spline 3D
frontend. Like the other routers, this depends *only* on `OasisFacade` —
it never imports `OasisRepository` or `GamificationEngine` directly. All
of that wiring lives in `app.presentation.dependencies`.
"""

from __future__ import annotations

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.oasis_facade import OasisFacade
from app.core.exceptions import PersistenceError
from app.presentation.auth import get_current_user_id, require_matching_user
from app.presentation.dependencies import get_oasis_facade
from app.presentation.schemas.oasis import OasisStateDTO

logger = logging.getLogger(__name__)

router = APIRouter()

# Generic, safe message returned to the client whenever a Persistence-layer
# failure occurs. The real exception (which may contain raw database error
# text, table/column names, or other internal details) is logged
# server-side via `logger.exception` instead of being sent to the client.
_UPSTREAM_ERROR_DETAIL = "Failed to load Oasis data, please try again later."


@router.get(
    "/{user_id}",
    response_model=OasisStateDTO,
    summary="Get a user's persisted Oasis state and derived 3D scene environment",
)
async def get_oasis_state(
    user_id: UUID,
    facade: OasisFacade = Depends(get_oasis_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> OasisStateDTO:
    """
    Returns the user's persisted, cumulative Oasis stats (growth_level,
    health_score, streak days) plus the dynamic environmental variables
    (weather_condition, visual_aura, streak_multiplier, mood_message)
    derived from them for the Spline scene.

    This is a single indexed row read, not a replay of the user's
    transaction history — safe to call on every Oasis scene load.
    """
    require_matching_user(str(user_id), current_user_id)
    try:
        return await run_in_threadpool(facade.get_oasis_state, str(user_id))
    except PersistenceError as exc:
        logger.exception("Failed to fetch Oasis state for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc