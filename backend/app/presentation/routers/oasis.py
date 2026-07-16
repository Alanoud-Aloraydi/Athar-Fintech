"""
Oasis Router (Presentation layer).

Exposes the optimized Oasis-state endpoint consumed by the Spline 3D
frontend. Like the other routers, this depends *only* on `OasisFacade` —
it never imports `OasisRepository` or `GamificationEngine` directly. All
of that wiring lives in `app.presentation.dependencies`.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.oasis_facade import OasisFacade
from app.core.exceptions import PersistenceError
from app.presentation.dependencies import get_oasis_facade
from app.presentation.schemas.oasis import OasisStateDTO

router = APIRouter()


@router.get(
    "/{user_id}",
    response_model=OasisStateDTO,
    summary="Get a user's persisted Oasis state and derived 3D scene environment",
)
async def get_oasis_state(
    user_id: UUID,
    facade: OasisFacade = Depends(get_oasis_facade),
) -> OasisStateDTO:
    """
    Returns the user's persisted, cumulative Oasis stats (growth_level,
    health_score, streak days) plus the dynamic environmental variables
    (weather_condition, visual_aura, streak_multiplier, mood_message)
    derived from them for the Spline scene.

    This is a single indexed row read, not a replay of the user's
    transaction history — safe to call on every Oasis scene load.
    """
    try:
        return await run_in_threadpool(facade.get_oasis_state, str(user_id))
    except PersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to fetch Oasis state: {exc}",
        ) from exc
