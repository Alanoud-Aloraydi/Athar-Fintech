
"""
Transaction DTOs (Presentation layer).

These schemas define the API's public contract for transaction ingestion.
Presentation is permitted to depend on Business (one-directional layering),
so `TransactionResponseDTO` reuses `CategoryEnum` and `OasisImpact` directly
from the Business layer rather than duplicating them — this keeps the
Oasis-impact shape guaranteed to match what the Gamification Engine
actually produces.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.business.categorization.models import CategoryEnum
from app.business.gamification.models import OasisImpact

# Mirrors the transaction "type" values understood by the Gamification
# Engine and the `transactions.type` column — kept as a Literal (rather
# than a full Enum) since the Presentation layer only needs to validate
# these two accepted values on inbound requests.
TransactionType = Literal["EXPENSE", "INCOME"]


class TransactionCreateDTO(BaseModel):
    """
    Inbound payload for `POST /transactions/`.

    `type_enum` is aliased to the JSON key `"type"` to match the
    frontend's payload shape (`{"type": "EXPENSE", ...}`). The Python
    attribute stays `type_enum` throughout the rest of the codebase
    (`type` alone would shadow the built-in) — `populate_by_name=True`
    means the model still also accepts `type_enum` directly (e.g. when
    constructed programmatically in tests), so neither call site breaks.

    Note: any `"category"` key sent by the client is silently ignored —
    category is derived server-side by the Categorization Engine, not
    accepted as client input.

    `idempotency_key` is optional but recommended: the Flutter client
    should generate one UUID per logical submission (e.g. once when the
    user taps "save", reused verbatim across any automatic network
    retries for that same tap) so a dropped response never results in a
    double-charged balance. Omitting it just means this particular
    request isn't idempotency-protected — it always inserts a fresh
    transaction.
    """

    model_config = ConfigDict(populate_by_name=True)

    user_id: UUID = Field(description="UUID of the authenticated user")
    amount: float = Field(gt=0, description="Transaction amount; must be positive")
    description: str = Field(
        min_length=1, max_length=500, description="Raw merchant/transaction description"
    )
    type_enum: TransactionType = Field(
        alias="type", description='Either "EXPENSE" or "INCOME"'
    )
    idempotency_key: str | None = Field(
        default=None,
        max_length=200,
        description=(
            "Optional client-generated key, unique per user, identifying this "
            "logical submission. Reuse the same key across retries of the same "
            "user action to avoid double-charging the balance on a network retry."
        ),
    )


class TransactionResponseDTO(BaseModel):
    """
    Outbound response for a successfully processed transaction.

    Combines the persisted transaction's details with the `OasisImpact`
    computed for it, so the Flutter client can update the 3D Oasis scene
    from a single response without a follow-up request.
    """

    model_config = ConfigDict(populate_by_name=True)

    id: UUID
    user_id: UUID
    description: str
    amount: float
    category: CategoryEnum
    type_enum: TransactionType = Field(alias="type")
    created_at: datetime
    oasis_impact: OasisImpact
    is_replay: bool = Field(
        default=False,
        description=(
            "True if this response came from an idempotent replay (a prior "
            "request with the same idempotency_key already succeeded) rather "
            "than a fresh insert — the balance and Oasis state were NOT "
            "mutated again."
        ),
    )
    is_unusual_spend: bool = Field(
        default=False,
        description=(
            "True if this EXPENSE is unusually large relative to the user's "
            "own historical average for its category (mean + 2 standard "
            "deviations, computed from their own past transactions only)."
        ),
    )
