
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
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.business.facades.transaction_facade import TransactionFacade
from app.core.exceptions import PersistenceError, ProfileNotFoundError
from app.presentation.auth import get_current_user_id, require_matching_user
from app.presentation.dependencies import get_transaction_facade
from app.presentation.schemas.analytics import OpenBankingSyncResponseDTO
from app.presentation.schemas.transactions import (
    TransactionCreateDTO,
    TransactionHistoryItemDTO,
    TransactionResponseDTO,
)

logger = logging.getLogger(__name__)

router = APIRouter()

# Generic, safe message returned to the client whenever a Persistence-layer
# failure occurs. The real exception (which may contain raw database error
# text, table/column names, or other internal details) is logged
# server-side via `logger.exception` instead of being sent to the client.
_UPSTREAM_ERROR_DETAIL = "Failed to process your transaction request, please try again later."


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


@router.post(
    "/sync_open_banking/{user_id}",
    response_model=OpenBankingSyncResponseDTO,
    status_code=status.HTTP_200_OK,
    summary="Simulate Alinma Open Banking sync — generates and stores mock Saudi transactions",
)
async def sync_open_banking(
    user_id: UUID,
    facade: TransactionFacade = Depends(get_transaction_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> OpenBankingSyncResponseDTO:
    """
    Mimics an Alinma Open Banking pull. Generates a realistic set of mock
    Saudi transactions (merchants, amounts, types) and stores them through
    the normal Facade pipeline so the Categorization Engine and Gamification
    Engine both run. Idempotency keys scoped to today's date prevent duplicate
    entries if the user syncs more than once in the same day.
    """
    require_matching_user(str(user_id), current_user_id)

    from datetime import date as _date

    # ── Permanent baseline transactions ───────────────────────────────
    # Date-free idempotency keys → inserted exactly once, never again.
    # Includes:
    #  • Five Half-Million Coffee baseline entries (μ≈16 SAR) so the
    #    Z-Score leave-one-out fires immediately on first sync.
    #  • The WPS salary (18,000 SAR) that drives income-aware metrics.
    _BASELINE: list[dict] = [
        # Coffee Z-Score baseline (μ=16 SAR, σ≈1.58)
        {"description": "Half Million Coffee Shop", "amount": 14.0,    "type": "EXPENSE", "key": "alinma_baseline_coffee_1"},
        {"description": "Half Million Coffee Shop", "amount": 15.0,    "type": "EXPENSE", "key": "alinma_baseline_coffee_2"},
        {"description": "Half Million Coffee Shop", "amount": 16.0,    "type": "EXPENSE", "key": "alinma_baseline_coffee_3"},
        {"description": "Half Million Coffee Shop", "amount": 17.0,    "type": "EXPENSE", "key": "alinma_baseline_coffee_4"},
        {"description": "Half Million Coffee Shop", "amount": 18.0,    "type": "EXPENSE", "key": "alinma_baseline_coffee_5"},
        # WPS monthly salary — drives safe-to-spend & income-relative severity
        {"description": "Salary Transfer - WPS",   "amount": 18000.0, "type": "INCOME",  "key": "alinma_wps_salary_primary"},
    ]

    # ── Daily rolling transactions ─────────────────────────────────────
    # Date-scoped keys → fresh insertion every new calendar day.
    # Highlights:
    #  • Elixir Bunn Coffee (150 SAR) → Z≈84, severity≈0.8% of income.
    #  • Tabby Installment  (250 SAR) → BNPL / committed obligation.
    #  • Monthly Family Transfer (1,500 SAR) → excluded from Z-Score pool.
    #  • Alinma Instant Savings (300 SAR) → boosts Oasis health.
    _MOCK: list[dict] = [
        # Entertainment / cafés & dining
        {"description": "Starbucks Coffee Riyadh",      "amount": 45.0,   "type": "EXPENSE"},
        {"description": "Restaurant AlBaik",             "amount": 32.0,   "type": "EXPENSE"},
        {"description": "Netflix Monthly Subscription",  "amount": 39.0,   "type": "EXPENSE"},
        {"description": "Spotify Music",                 "amount": 19.0,   "type": "EXPENSE"},
        {"description": "VOX Cinemas",                   "amount": 75.0,   "type": "EXPENSE"},
        # ⚡ Z-Score trigger: 150 SAR coffee vs 16 SAR baseline → Z≈84
        {"description": "Elixir Bunn Coffee",            "amount": 150.0,  "type": "EXPENSE"},
        # Groceries
        {"description": "Panda Supermarket",             "amount": 287.0,  "type": "EXPENSE"},
        {"description": "Othaim Markets",                "amount": 156.0,  "type": "EXPENSE"},
        {"description": "Tamimi Markets",                "amount": 198.0,  "type": "EXPENSE"},
        # Utilities
        {"description": "STC Monthly Bill",              "amount": 210.0,  "type": "EXPENSE"},
        {"description": "Saudi Electricity SEC",         "amount": 320.0,  "type": "EXPENSE"},
        # BNPL / committed obligation (Sharia-compliant installment)
        {"description": "Tabby Installment",             "amount": 250.0,  "type": "EXPENSE"},
        # Family support — EXPENSE, excluded from Z-Score anomaly pool
        {"description": "Monthly Family Transfer",       "amount": 1500.0, "type": "EXPENSE"},
        # Savings / income
        {"description": "Alinma Instant Savings",        "amount": 300.0,  "type": "INCOME"},
        {"description": "Alinma Auto-Save Transfer",     "amount": 1000.0, "type": "INCOME"},
    ]

    today = _date.today().isoformat()
    synced = 0
    already_synced = 0

    # Insert baseline first (permanent keys, inserted once ever).
    for mock in _BASELINE:
        payload = TransactionCreateDTO(
            user_id=user_id,
            amount=mock["amount"],
            description=mock["description"],
            type=mock["type"],
            idempotency_key=mock["key"],
        )
        try:
            result = await run_in_threadpool(facade.process_and_store, payload)
            if result.is_replay:
                already_synced += 1
            else:
                synced += 1
        except Exception:  # noqa: BLE001
            logger.warning("Skipped baseline transaction: %s", mock["description"])

    # Insert daily rolling transactions.
    for mock in _MOCK:
        key = f"alinma_sync_{today}_{mock['description'].replace(' ', '_')}"
        payload = TransactionCreateDTO(
            user_id=user_id,
            amount=mock["amount"],
            description=mock["description"],
            type=mock["type"],
            idempotency_key=key,
        )
        try:
            result = await run_in_threadpool(facade.process_and_store, payload)
            if result.is_replay:
                already_synced += 1
            else:
                synced += 1
        except Exception:  # noqa: BLE001
            logger.warning("Skipped Open Banking mock: %s", mock["description"])

    if synced == 0:
        msg = "محفظتك محدَّثة بالفعل — تمت مزامنتها اليوم مسبقاً ✅"
    else:
        msg = f"تمت مزامنة {synced} معاملة بنجاح من محفظة الإنماء 🔄"

    return OpenBankingSyncResponseDTO(
        synced_count=synced,
        already_synced=already_synced,
        message=msg,
    )


@router.get(
    "/{user_id}",
    response_model=list[TransactionHistoryItemDTO],
    summary="Get a user's full transaction history, most recent first",
)
async def get_transaction_history(
    user_id: UUID,
    facade: TransactionFacade = Depends(get_transaction_facade),
    current_user_id: str = Depends(get_current_user_id),
) -> list[TransactionHistoryItemDTO]:
    """
    Returns every transaction belonging to `user_id`, most recent first —
    powers the Flutter "Transactions" screen so the full ledger (not just
    the dashboard's aggregated totals) is visible in the app.
    """
    require_matching_user(str(user_id), current_user_id)
    try:
        return await run_in_threadpool(facade.get_history, str(user_id))
    except PersistenceError as exc:
        logger.exception("Failed to fetch transaction history for user_id=%s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=_UPSTREAM_ERROR_DETAIL,
        ) from exc


