"""
Transaction Router (Presentation layer).

Exposes the transaction-ingestion endpoint consumed by the Flutter client.
This router depends *only* on `TransactionFacade` — it never imports or
calls the Categorization Engine, Gamification Engine, or either
repository directly. All of that wiring lives in
`app.presentation.dependencies`.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.transaction_facade import TransactionFacade
from app.core.exceptions import PersistenceError, ProfileNotFoundError
from app.presentation.auth import get_current_user_id, require_matching_user
from app.presentation.dependencies import get_transaction_facade
from app.presentation.schemas.transactions import TransactionCreateDTO, TransactionResponseDTO

logger = logging.getLogger(__name__)

router = APIRouter()

# Generic, safe message returned to the client whenever a Persistence-layer
# failure occurs. The real exception (which may contain raw database error
# text, table/column names, or other internal details) is logged
# server-side via `logger.exception` instead of being sent to the client.
_UPSTREAM_ERROR_DETAIL = "Failed to save your transaction, please try again later."


@router.post(
    "/",
    response_model=TransactionResponseDTO,
    status_code=status.HTTP_201_CREATED,
    summary="Ingest, categorize, and store a new transaction",
)
async def create_transaction(
    payload: TransactionCreateDTO,
    facade: TransactionFacade = Depends(get_transaction_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> TransactionResponseDTO:
    """
    Accepts a raw transaction, runs it through the full Facade pipeline
    (categorize → evaluate Oasis impact → persist → roll into active
    goal if applicable), and returns the resulting `TransactionResponseDTO`.

    The Facade's `process_and_store` is synchronous (it wraps blocking
    Supabase I/O), so it's offloaded to FastAPI's threadpool via
    `run_in_threadpool` to avoid blocking the event loop.
    """
    # user_id here comes from the request BODY, not the URL path (see
    # TransactionCreateDTO) -- still must match the authenticated caller,
    # otherwise anyone could post transactions into someone else's account.
    require_matching_user(str(payload.user_id), current_user_id)
    try:
        return await run_in_threadpool(facade.process_and_store, payload)
    except ProfileNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except PersistenceError as exc:
        logger.exception(
            "Failed to persist transaction for user_id=%s", payload.user_id
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc
    except Exception as exc:  # noqa: BLE001 - final safety net, never leak internals
        logger.exception(
            "Unexpected error while processing transaction for user_id=%s",
            payload.user_id,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while processing the transaction.",
        ) from exc