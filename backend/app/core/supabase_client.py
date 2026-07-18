
"""
Supabase client factories.

Two client types are exposed:

1. ``get_supabase_client()`` — singleton initialized with the service-role
   key.  This key bypasses Row Level Security and must be used ONLY for
   operations that genuinely need elevated privileges (e.g. cross-user
   writes, admin tasks).  Kept for backward-compatibility; new code should
   prefer ``get_user_supabase_client`` for user-scoped reads and writes.

2. ``get_user_supabase_client(token)`` — per-request client initialized
   with the anon key and then authenticated as the calling user by attaching
   their Supabase JWT to every PostgREST request.  This client DOES respect
   Row Level Security, providing a database-layer ownership check that is
   independent of the application-level ``require_matching_user`` guard.

Defense-in-depth: using the per-user client means that even if an
application-layer authorization check is accidentally omitted, Supabase's
RLS policies (see migration 006) will still reject cross-user queries at
the database level.
"""

from functools import lru_cache

from supabase import Client, create_client

from app.core.config import settings


@lru_cache
def get_supabase_client() -> Client:
    """
    Returns a cached, singleton Supabase ``Client`` initialized with the
    service-role key (bypasses RLS).

    ``lru_cache`` guarantees the client (and its underlying HTTP connection
    pool) is constructed exactly once per process and reused across every
    call site.

    Use this only for operations that require elevated access.  For
    user-scoped database access, call ``get_user_supabase_client`` instead.

    Raises RuntimeError if SUPABASE_URL or SUPABASE_SERVICE_KEY are not set.
    """
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_KEY:
        raise RuntimeError(
            "Supabase credentials are not configured. "
            "Set SUPABASE_URL and SUPABASE_SERVICE_KEY as Replit Secrets "
            "and restart the workflow."
        )
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


def get_user_supabase_client(token: str) -> Client:
    """
    Returns a Supabase ``Client`` that authenticates every PostgREST request
    as the user who owns ``token``.

    Unlike the service-role client, this client respects Row Level Security:
    the database will automatically reject any query that tries to read or
    write rows that don't belong to the authenticated user (once RLS policies
    are applied via migration 006).

    The client is created fresh per request (not cached) because each caller
    has a distinct JWT.  ``create_client`` is cheap — it only sets
    configuration and does not open a network connection until the first
    query.

    Args:
        token: A valid Supabase access token (the raw JWT string, without the
               ``Bearer `` prefix) obtained from the request's Authorization
               header.

    Raises:
        RuntimeError: If SUPABASE_URL or SUPABASE_ANON_KEY are not configured.
    """
    if not settings.SUPABASE_URL or not settings.SUPABASE_ANON_KEY:
        raise RuntimeError(
            "Supabase anon key is not configured. "
            "Set SUPABASE_URL and SUPABASE_ANON_KEY as Replit Secrets "
            "and restart the workflow."
        )
    client = create_client(settings.SUPABASE_URL, settings.SUPABASE_ANON_KEY)
    # Attach the user's JWT to all PostgREST (table + RPC) requests so that
    # Supabase's auth.uid() resolves to this user's UUID inside RLS policies
    # and SECURITY INVOKER functions.
    client.postgrest.auth(token)
    return client


# Lazy accessor — do NOT call get_supabase_client() at module level.
# Import and call get_supabase_client() only inside request handlers or
# repository methods so the server can start without Supabase credentials.
def get_supabase() -> Client:
    """Convenience alias for the service-role client; raises RuntimeError if credentials are missing."""
    return get_supabase_client()


