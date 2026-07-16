
"""
Analytics Router (Presentation layer).

Exposes the spending/Oasis summary endpoints consumed by the Flutter
client. Like `transactions.py` and `goals.py`, this router depends
*only* on `AnalyticsFacade` — it never imports `TransactionRepository`
or `GamificationEngine` directly. All of that wiring lives in
`app.presentation.dependencies`.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.analytics_facade import AnalyticsFacade
from app.core.exceptions import PersistenceError, ProfileNotFoundError
from app.presentation.dependencies import get_analytics_facade
from app.presentation.schemas.analytics import AnalyticsSummaryDTO, DashboardSummaryDTO

router = APIRouter()


@router.get(
    "/{user_id}",
    response_model=DashboardSummaryDTO,
    summary="Get the unified dashboard summary: balance, goal progress, expenses, Smart Insights",
)
async def get_dashboard_summary(
    user_id: UUID,
    facade: AnalyticsFacade = Depends(get_analytics_facade),
) -> DashboardSummaryDTO:
    """
    Returns everything the Flutter dashboard needs in one call: current
    balance, active-goal progress, a per-category expense breakdown,
    cumulative Oasis scores, and the Smart Insights block (spending
    velocity, a projected goal-completion date, and a dynamic trajectory
    message).
    """
    try:
        return await run_in_threadpool(facade.get_dashboard_summary, str(user_id))
    except ProfileNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except PersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to build dashboard summary: {exc}",
        ) from exc


@router.get(
    "/{user_id}/summary",
    response_model=AnalyticsSummaryDTO,
    summary="Get a user's income/expense/category breakdown and Oasis scores",
)
async def get_analytics_summary(
    user_id: UUID,
    facade: AnalyticsFacade = Depends(get_analytics_facade),
) -> AnalyticsSummaryDTO:
    """
    Returns the spending/Oasis-scores summary for `user_id`: income/expense
    totals, a per-category spending breakdown, and the persisted cumulative
    Oasis growth/health scores. Kept alongside `get_dashboard_summary` for
    existing clients that only need this narrower shape.
    """
    try:
        return await run_in_threadpool(facade.get_summary, str(user_id))
    except PersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to build analytics summary: {exc}",
        ) from exc
