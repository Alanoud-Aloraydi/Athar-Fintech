"""
Presentation-layer dependency wiring.

This module is the *only* place in the Presentation layer allowed to know
about Business-layer engines and Persistence-layer repositories. Routers
depend exclusively on the `get_*_facade` functions exposed here, so they
never import an engine or a repository directly — that was the leak
identified in the original `transactions.py` router.

ACCESS CONTROL — defense-in-depth
----------------------------------
All user-scoped repository providers below use ``get_user_scoped_client``
rather than the service-role singleton.  ``get_user_scoped_client`` creates a
Supabase client authenticated with the caller's own JWT, so every PostgREST
query it issues runs as that user.  When Row Level Security is enabled on the
database tables (see migration 006), Supabase will automatically reject any
query that tries to touch another user's rows — providing a database-layer
ownership check that is independent of the application-level
``require_matching_user`` guard in each route handler.

The service-role client (``get_supabase_client``) is intentionally NOT used
here; it is kept only for genuine administrative operations that need to
bypass RLS.
"""

from __future__ import annotations

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from supabase import Client

from app.business.analytics.insights_engine import InsightsEngine
from app.business.categorization.engine import CategorizationEngine, get_categorization_engine
from app.business.facades.analytics_facade import AnalyticsFacade
from app.business.facades.oasis_facade import OasisFacade
from app.business.facades.transaction_facade import TransactionFacade
from app.business.facades.goal_facade import GoalFacade
from app.business.gamification.engine import GamificationEngine, get_gamification_engine
from app.core.supabase_client import get_supabase_client, get_user_supabase_client
from app.persistence.repositories.goal_repo import GoalRepository
from app.persistence.repositories.oasis_repo import OasisRepository
from app.persistence.repositories.profile_repo import ProfileRepository
from app.persistence.repositories.transaction_repo import TransactionRepository
from app.presentation.auth import _UNAUTHORIZED, _bearer_scheme


# ---------------------------------------------------------------------------
# User-scoped Supabase client
# ---------------------------------------------------------------------------

def get_user_scoped_client(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> Client:
    """
    FastAPI dependency — returns a Supabase client authenticated as the
    requesting user.

    The client is initialized with the anon key and then has the caller's
    Bearer JWT attached to every PostgREST request (via
    ``client.postgrest.auth(token)``).  This means:

    * ``auth.uid()`` inside RLS policies resolves to the caller's UUID.
    * Row Level Security policies (migration 006) are enforced by the
      database, not just by our application code.

    The token is NOT re-validated here — ``get_current_user_id`` (already
    called by every authenticated route via ``Depends``) handles signature
    verification.  This dependency simply threads the raw token into the
    client so the database can enforce ownership independently.

    Raises HTTP 401 if no Bearer token is present (consistent with the auth
    module's behaviour so callers get a single, uniform error shape).
    """
    if credentials is None or not credentials.credentials:
        raise _UNAUTHORIZED
    return get_user_supabase_client(credentials.credentials)


# --- Repository providers -------------------------------------------------


def get_transaction_repository(
    client: Client = Depends(get_user_scoped_client),
) -> TransactionRepository:
    return TransactionRepository(client)


def get_goal_repository(
    client: Client = Depends(get_user_scoped_client),
) -> GoalRepository:
    return GoalRepository(client)


# NOTE (profiles + oasis_states): these two repositories use the service-role
# client rather than the user-scoped client. Under the RLS model (migrations
# 006/007) the `authenticated` role was never granted INSERT on `profiles`
# (needed by ensure_profile's upsert) nor any privilege on `oasis_states`, so a
# per-user client fails with "permission denied" and the dashboard 502s. Both
# repositories only ever touch rows keyed by the caller's own user_id, and every
# route still enforces `require_matching_user` against the JWT-verified id, so
# provisioning/reading these via the admin client is safe. (Migration 008 adds
# the missing grants for teams that prefer to keep these on the user client.)
def get_oasis_repository() -> OasisRepository:
    return OasisRepository(get_supabase_client())


def get_profile_repository() -> ProfileRepository:
    return ProfileRepository(get_supabase_client())


# --- Engine providers ------------------------------------------------------


def get_insights_engine() -> InsightsEngine:
    return InsightsEngine()


# --- Facade providers (what routers actually depend on) ---------------------


def get_transaction_facade(
    categorization_engine: CategorizationEngine = Depends(get_categorization_engine),
    gamification_engine: GamificationEngine = Depends(get_gamification_engine),
    transaction_repository: TransactionRepository = Depends(get_transaction_repository),
    goal_repository: GoalRepository = Depends(get_goal_repository),
    profile_repository: ProfileRepository = Depends(get_profile_repository),
) -> TransactionFacade:
    return TransactionFacade(
        categorization_engine=categorization_engine,
        gamification_engine=gamification_engine,
        transaction_repository=transaction_repository,
        goal_repository=goal_repository,
        profile_repository=profile_repository,
    )


def get_goal_facade(
    goal_repository: GoalRepository = Depends(get_goal_repository),
    transaction_repository: TransactionRepository = Depends(get_transaction_repository),
) -> GoalFacade:
    return GoalFacade(
        goal_repository=goal_repository,
        transaction_repository=transaction_repository,
    )


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
    categorization_engine: CategorizationEngine = Depends(get_categorization_engine),
) -> OasisFacade:
    return OasisFacade(
        oasis_repository=oasis_repository,
        gamification_engine=gamification_engine,
        categorization_engine=categorization_engine,
    )
