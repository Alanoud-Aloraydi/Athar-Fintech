
"""
Presentation-layer dependency wiring.

This module is the *only* place in the Presentation layer allowed to know
about Business-layer engines and Persistence-layer repositories. Routers
depend exclusively on the `get_*_facade` functions exposed here, so they
never import an engine or a repository directly — that was the leak
identified in the original `transactions.py` router.
"""

from __future__ import annotations

from fastapi import Depends
from supabase import Client

from app.business.analytics.insights_engine import InsightsEngine
from app.business.categorization.engine import CategorizationEngine, get_categorization_engine
from app.business.facades.analytics_facade import AnalyticsFacade
from app.business.facades.oasis_facade import OasisFacade
from app.business.facades.transaction_facade import TransactionFacade
from app.business.facades.goal_facade import GoalFacade
from app.business.gamification.engine import GamificationEngine, get_gamification_engine
from app.core.supabase_client import get_supabase_client
from app.persistence.repositories.goal_repo import GoalRepository
from app.persistence.repositories.oasis_repo import OasisRepository
from app.persistence.repositories.profile_repo import ProfileRepository
from app.persistence.repositories.transaction_repo import TransactionRepository


# --- Repository providers -------------------------------------------------


def get_transaction_repository(
    client: Client = Depends(get_supabase_client),
) -> TransactionRepository:
    return TransactionRepository(client)


def get_goal_repository(client: Client = Depends(get_supabase_client)) -> GoalRepository:
    return GoalRepository(client)


def get_oasis_repository(client: Client = Depends(get_supabase_client)) -> OasisRepository:
    return OasisRepository(client)


def get_profile_repository(client: Client = Depends(get_supabase_client)) -> ProfileRepository:
    return ProfileRepository(client)


# --- Engine providers ------------------------------------------------------


def get_insights_engine() -> InsightsEngine:
    return InsightsEngine()


# --- Facade providers (what routers actually depend on) ---------------------


def get_transaction_facade(
    categorization_engine: CategorizationEngine = Depends(get_categorization_engine),
    gamification_engine: GamificationEngine = Depends(get_gamification_engine),
    transaction_repository: TransactionRepository = Depends(get_transaction_repository),
    goal_repository: GoalRepository = Depends(get_goal_repository),
) -> TransactionFacade:
    return TransactionFacade(
        categorization_engine=categorization_engine,
        gamification_engine=gamification_engine,
        transaction_repository=transaction_repository,
        goal_repository=goal_repository,
    )


def get_goal_facade(
    goal_repository: GoalRepository = Depends(get_goal_repository),
) -> GoalFacade:
    return GoalFacade(goal_repository=goal_repository)


def get_analytics_facade(
    transaction_repository: TransactionRepository = Depends(get_transaction_repository),
    oasis_repository: OasisRepository = Depends(get_oasis_repository),
    profile_repository: ProfileRepository = Depends(get_profile_repository),
    goal_repository: GoalRepository = Depends(get_goal_repository),
    insights_engine: InsightsEngine = Depends(get_insights_engine),
) -> AnalyticsFacade:
    return AnalyticsFacade(
        transaction_repository=transaction_repository,
        oasis_repository=oasis_repository,
        profile_repository=profile_repository,
        goal_repository=goal_repository,
        insights_engine=insights_engine,
    )


def get_oasis_facade(
    oasis_repository: OasisRepository = Depends(get_oasis_repository),
    gamification_engine: GamificationEngine = Depends(get_gamification_engine),
) -> OasisFacade:
    return OasisFacade(
        oasis_repository=oasis_repository,
        gamification_engine=gamification_engine,
    )
