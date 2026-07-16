
"""
Goal Router (Presentation layer).

Exposes Financial Goal creation, retrieval, and lifecycle transitions,
consumed by the Flutter client. Like `transactions.py`, this router
depends *only* on `GoalFacade` â€” it never imports `GoalRepository`
directly. All of that wiring lives in `app.presentation.dependencies`.

Lifecycle rule: a user may have at most one ACTIVE goal at a time,
enforced atomically at the database (see
`supabase/goal_lifecycle_functions.sql`). `create_goal` below returns
409 Conflict if the user already has one â€” the client must call
`transition_goal_status` first to move it to COMPLETED or ARCHIVED.

Note: `GoalCreateDTO` intentionally has no `user_id` field (it's an
inbound request body describing only the goal itself), so `user_id` is
taken from the path here rather than the payload. In a codebase with
auth wired up, this would instead come from an authenticated-user
dependency rather than a raw path parameter.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.goal_facade import GoalFacade
from app.core.exceptions import GoalConflictError, GoalNotFoundError, PersistenceError
from app.presentation.dependencies import get_goal_facade
from app.presentation.schemas.goals import GoalCreateDTO, GoalResponseDTO, GoalStatusUpdateDTO

router = APIRouter()


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
) -> GoalResponseDTO:
    """
    Creates a new `ACTIVE` Financial Goal for `user_id` from the given payload.

    Returns 409 Conflict if the user already has an ACTIVE goal â€” use
    `PATCH /goals/{user_id}/{goal_id}/status` to complete or archive it
    first.
    """
    try:
        return await run_in_threadpool(facade.create_goal, str(user_id), payload)
    except GoalConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except PersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to persist goal: {exc}",
        ) from exc


@router.patch(
    "/{user_id}/{goal_id}/status",
    response_model=GoalResponseDTO,
    summary="Transition an ACTIVE goal to COMPLETED or ARCHIVED",
)
async def transition_goal_status(
    user_id: UUID,
    goal_id: UUID,
    payload: GoalStatusUpdateDTO,
    facade: GoalFacade = Depends(get_goal_facade),
) -> GoalResponseDTO:
    """
    Ends a goal's ACTIVE lifecycle. Required before `create_goal` will
    succeed for a user who already has an ACTIVE goal.
    """
    try:
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
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to transition goal: {exc}",
        ) from exc


@router.get(
    "/{user_id}/active",
    response_model=GoalResponseDTO | None,
    summary="Fetch a user's currently active Financial Goal, if any",
)
async def get_active_goal(
    user_id: UUID,
    facade: GoalFacade = Depends(get_goal_facade),
) -> GoalResponseDTO | None:
    """Returns the user's active goal, or `null` if they don't have one."""
    try:
        return await run_in_threadpool(facade.get_active_goal, str(user_id))
    except PersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to fetch active goal: {exc}",
        ) from exc


