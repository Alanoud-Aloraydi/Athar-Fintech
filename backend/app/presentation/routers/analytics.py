"""
Analytics Router (Presentation layer).

Exposes the spending/Oasis summary endpoints consumed by the Flutter
client. Like `transactions.py` and `goals.py`, this router depends
*only* on `AnalyticsFacade` — it never imports `TransactionRepository`
or `GamificationEngine` directly. All of that wiring lives in
`app.presentation.dependencies`.
"""

from __future__ import annotations

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.analytics_facade import AnalyticsFacade
from app.core.exceptions import PersistenceError, ProfileNotFoundError
from app.presentation.auth import get_current_user_id, require_matching_user
from app.presentation.dependencies import get_analytics_facade
from app.presentation.schemas.analytics import AnalyticsSummaryDTO, DashboardSummaryDTO

logger = logging.getLogger(__name__)

router = APIRouter()

# Generic, safe message returned to the client whenever a Persistence-layer
# failure occurs. The real exception (which may contain raw database error
# text, table/column names, or other internal details) is logged
# server-side via `logger.exception` instead of being sent to the client.
_UPSTREAM_ERROR_DETAIL = "Failed to load data, please try again later."


@router.get(
    "/{user_id}",
    response_model=DashboardSummaryDTO,
    summary="Get the unified dashboard summary: balance, goal progress, expenses, Smart Insights",
)
async def get_dashboard_summary(
    user_id: UUID,
    facade: AnalyticsFacade = Depends(get_analytics_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> DashboardSummaryDTO:
    """
    Returns everything the Flutter dashboard needs in one call: current
    balance, active-goal progress, a per-category expense breakdown,
    cumulative Oasis scores, and the Smart Insights block (spending
    velocity, a projected goal-completion date, and a dynamic trajectory
    message).
    """
    require_matching_user(str(user_id), current_user_id)
    try:
        return await run_in_threadpool(facade.get_dashboard_summary, str(user_id))
    except ProfileNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except PersistenceError as exc:
        logger.exception("Failed to build dashboard summary for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc


@router.get(
    "/{user_id}/summary",
    response_model=AnalyticsSummaryDTO,
    summary="Get a user's income/expense/category breakdown and Oasis scores",
)
async def get_analytics_summary(
    user_id: UUID,
    facade: AnalyticsFacade = Depends(get_analytics_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> AnalyticsSummaryDTO:
    """
    Returns the spending/Oasis-scores summary for `user_id`: income/expense
    totals, a per-category spending breakdown, and the persisted cumulative
    Oasis growth/health scores. Kept alongside `get_dashboard_summary` for
    existing clients that only need this narrower shape.
    """
    require_matching_user(str(user_id), current_user_id)
    try:
        return await run_in_threadpool(facade.get_summary, str(user_id))
    except PersistenceError as exc:
        logger.exception("Failed to build analytics summary for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc