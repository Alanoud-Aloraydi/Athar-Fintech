
"""
Categorization domain models.

`CategoryEnum` is the single source of truth for spending categories used
across the Categorization Engine, the Gamification Engine, and the
Presentation-layer DTOs (goals + transactions) that reference a category.
"""
from __future__ import annotations

from enum import Enum


class CategoryEnum(str, Enum):
    """Spending category assigned to a transaction (and, by extension, a goal)."""

    GROCERIES = "GROCERIES"
    UTILITIES = "UTILITIES"
    ENTERTAINMENT = "ENTERTAINMENT"
    SAVINGS = "SAVINGS"
    UNCATEGORIZED = "UNCATEGORIZED"


