
"""
Categorization domain models.

`CategoryEnum` is the single source of truth for spending categories used
across the Categorization Engine, the Gamification Engine, and the
Presentation-layer DTOs (goals + transactions) that reference a category.

Covers global FinTech standards: Food, Groceries, Utilities, Entertainment,
Health, Transport, Housing, Shopping, Savings, Uncategorized.
"""
from __future__ import annotations

from enum import Enum


class CategoryEnum(str, Enum):
    """Global FinTech spending category assigned to a transaction or goal."""

    FOOD = "FOOD"                       # Restaurants, cafes, fast food
    GROCERIES = "GROCERIES"             # Supermarkets, hypermarkets
    UTILITIES = "UTILITIES"             # Phone, electricity, water, internet
    ENTERTAINMENT = "ENTERTAINMENT"     # Cinema, gaming, streaming
    HEALTH = "HEALTH"                   # Pharmacy, clinics, hospitals
    TRANSPORT = "TRANSPORT"             # Uber, taxi, fuel
    HOUSING = "HOUSING"                 # Rent, home maintenance
    SHOPPING = "SHOPPING"               # Retail, online stores
    SAVINGS = "SAVINGS"                 # Savings, investments, transfers
    UNCATEGORIZED = "UNCATEGORIZED"     # No matching rule found
