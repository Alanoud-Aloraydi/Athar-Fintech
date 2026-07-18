"""
Goal Router (Presentation layer).

Exposes Financial Goal creation, retrieval, and lifecycle transitions,
consumed by the Flutter client. Like `transactions.py`, this router
depends *only* on `GoalFacade` — it never imports `GoalRepository`
directly. All of that wiring lives in `app.presentation.dependencies`.

Lifecycle rule: a user may have at most one ACTIVE goal at a time,
enforced atomically at the database (see
`supabase/goal_lifecycle_functions.sql`). `create_goal` below returns
409 Conflict if the user already has one — the client must call
`transition_goal_status` first to move it to COMPLETED or ARCHIVED.

Note: `GoalCreateDTO` intentionally has no `user_id` field (it's an
inbound request body describing only the goal itself), so `user_id` is
taken from the path here rather than the payload. In a codebase with
auth wired up, this would instead come from an authenticated-user
dependency rather than a raw path parameter.
"""

from __future__ import annotations

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.goal_facade import GoalFacade
from app.core.exceptions import GoalConflictError, GoalNotFoundError, PersistenceError
from app.presentation.auth import get_current_user_id, require_matching_user
from app.presentation.dependencies import get_goal_facade
from app.presentation.schemas.goals import GoalCreateDTO, GoalResponseDTO, GoalStatusUpdateDTO

logger = logging.getLogger(__name__)

router = APIRouter()

# Generic, safe message returned to the client whenever a Persistence-layer
# failure occurs. The real exception (which may contain raw database error
# text, table/column names, or other internal details) is logged
# server-side via `logger.exception` instead of being sent to the client.
_UPSTREAM_ERROR_DETAIL = "Failed to save your goal, please try again later."


@router.post(
    "/{user_id}",
    response_model=GoalResponseDTO,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new Financial Goal for a user",
)
async def create_goal(
    user_id: UUID,
    payload: GoalCreateDTO,
    facade: GoalFacade = Depends(get_goal_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> GoalResponseDTO:
    """
    Creates a new `ACTIVE` Financial Goal for `user_id` from the given payload.

    Returns 409 Conflict if the user already has an ACTIVE goal — use
    `PATCH /goals/{user_id}/{goal_id}/status` to complete or archive it
    first.
    """
    require_matching_user(str(user_id), current_user_id)
    try:
        return await run_in_threadpool(facade.create_goal, str(user_id), payload)
    except GoalConflictError as exc:
        # This message is a deliberate, application-level business message
        # (no raw DB/internal details) -- safe to return verbatim.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except PersistenceError as exc:
        logger.exception("Failed to persist goal for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc


@router.patch(
    "/{user_id}/{goal_id}/status",
    response_model=GoalResponseDTO,
    summary="Transition an ACTIVE goal to COMPLETED, CANCELLED, or ARCHIVED",
)
async def transition_goal_status(
    user_id: UUID,
    goal_id: UUID,
    payload: GoalStatusUpdateDTO,
    facade: GoalFacade = Depends(get_goal_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> GoalResponseDTO:
    """
    Ends a goal's ACTIVE lifecycle. Three terminal states are supported:

    - **COMPLETED** — goal achieved; saved amount stays in the Savings Wallet.
    - **CANCELLED** — user exits early; saved amount is refunded to the Current
      Account as an INCOME transaction and the Oasis resets.
    - **ARCHIVED** — alias for COMPLETED (legacy; kept for backward compat).

    This call is required before `create_goal` will accept a new goal for a
    user who already has an ACTIVE goal.
    """
    require_matching_user(str(user_id), current_user_id)
    try:
        if payload.status == "CANCELLED":
            return await run_in_threadpool(
                facade.cancel_goal, str(user_id), str(goal_id)
            )
        return await run_in_threadpool(
            facade.transition_status, str(user_id), str(goal_id), payload.status
        )
    except GoalNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except GoalConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except PersistenceError as exc:
        logger.exception(
            "Failed to transition goal_id=%s for user_id=%s", goal_id, user_id
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc


@router.get(
    "/{user_id}/history",
    response_model=list[GoalResponseDTO],
    summary="Return all goals for a user across all statuses (Active, Completed, Archived)",
)
async def get_goal_history(
    user_id: UUID,
    facade: GoalFacade = Depends(get_goal_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> list[GoalResponseDTO]:
    """
    Returns every goal the user has ever created, most recent first.
    Useful for rendering a goal history timeline on the client.
    """
    require_matching_user(str(user_id), current_user_id)
    try:
        return await run_in_threadpool(facade.get_goal_history, str(user_id))
    except PersistenceError as exc:
        logger.exception("Failed to fetch goal history for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc


@router.get(
    "/{user_id}/active",
    response_model=GoalResponseDTO | None,
    summary="Fetch a user's currently active Financial Goal, if any",
)
async def get_active_goal(
    user_id: UUID,
    facade: GoalFacade = Depends(get_goal_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> GoalResponseDTO | None:
    """Returns the user's active goal, or `null` if they don't have one."""
    require_matching_user(str(user_id), current_user_id)
    try:
        return await run_in_threadpool(facade.get_active_goal, str(user_id))
    except PersistenceError as exc:
        logger.exception("Failed to fetch active goal for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc