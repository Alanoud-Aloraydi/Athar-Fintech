
"""
Goal DTOs (Presentation layer).

Define the API's public contract for Financial Goal creation and
retrieval. `category` reuses `CategoryEnum` directly from the Business
layer (Presentation â†’ Business is an allowed dependency direction),
keeping goal categories guaranteed to match the same set used by the
Categorization Engine.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.business.categorization.models import CategoryEnum


class GoalCreateDTO(BaseModel):
    """Inbound payload for `POST /goals/`."""

    title: str = Field(
        min_length=1, max_length=200, description="Short display name, e.g. 'Emergency Fund'"
    )
    target_amount: float = Field(gt=0, description="Total amount the user wants to reach")
    category: CategoryEnum = Field(description="Category this goal is tied to")
    deadline: date | None = Field(
        default=None, description="Optional target date to reach the goal by"
    )


class GoalResponseDTO(BaseModel):
    """Outbound representation of a persisted Financial Goal â€” mirrors `GoalRecord`."""

    id: UUID
    user_id: UUID
    title: str
    target_amount: float
    saved_amount: float
    category: CategoryEnum
    deadline: date | None
    status: str
    created_at: datetime


class GoalStatusUpdateDTO(BaseModel):
    """
    Inbound payload for `PATCH /goals/{user_id}/{goal_id}/status`.

    Only `COMPLETED` and `ARCHIVED` are legal targets â€” there is no
    supported path back to `ACTIVE` from a terminal state in this MVP.
    """

    status: Literal["COMPLETED", "ARCHIVED"] = Field(
        description="Terminal status to transition the goal to"
    )


