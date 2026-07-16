
"""
Transaction Router (Presentation layer).

Exposes the transaction-ingestion endpoint consumed by the Flutter client.
This router depends *only* on `TransactionFacade` â€” it never imports or
calls the Categorization Engine, Gamification Engine, or either
repository directly. All of that wiring lives in
`app.presentation.dependencies`.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.transaction_facade import TransactionFacade
from app.core.exceptions import PersistenceError, ProfileNotFoundError
from app.presentation.dependencies import get_transaction_facade
from app.presentation.schemas.transactions import TransactionCreateDTO, TransactionResponseDTO

router = APIRouter()


@router.post(
    "/",
    response_model=TransactionResponseDTO,
    status_code=status.HTTP_201_CREATED,
    summary="Ingest, categorize, and store a new transaction",
)
async def create_transaction(
    payload: TransactionCreateDTO,
    facade: TransactionFacade = Depends(get_transaction_facade),
) -> TransactionResponseDTO:
    """
    Accepts a raw transaction, runs it through the full Facade pipeline
    (categorize â†’ evaluate Oasis impact â†’ persist â†’ roll into active
    goal if applicable), and returns the resulting `TransactionResponseDTO`.

    The Facade's `process_and_store` is synchronous (it wraps blocking
    Supabase I/O), so it's offloaded to FastAPI's threadpool via
    `run_in_threadpool` to avoid blocking the event loop.
    """
    try:
        return await run_in_threadpool(facade.process_and_store, payload)
    except ProfileNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except PersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to persist transaction: {exc}",
        ) from exc
    except Exception as exc:  # noqa: BLE001 - final safety net, never leak internals
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while processing the transaction.",
        ) from exc


