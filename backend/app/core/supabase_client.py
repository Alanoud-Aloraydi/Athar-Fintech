
"""
Supabase client singleton.

Exposes a single, module-level `supabase` client instance, initialized with
the service-role key from `app.core.config`. This client is intended for
server-side use ONLY (it bypasses Row Level Security) and must never be
exposed to the Presentation layer directly â€” only Persistence-layer
repositories should import and use it.
"""

from functools import lru_cache

from supabase import Client, create_client

from app.core.config import settings


@lru_cache
def get_supabase_client() -> Client:
    """
    Returns a cached, singleton Supabase `Client` instance.

    `lru_cache` guarantees the client (and its underlying HTTP connection
    pool) is constructed exactly once per process and reused across every
    repository that depends on it.

    Raises RuntimeError if Supabase credentials are not configured — set
    SUPABASE_URL and SUPABASE_SERVICE_KEY as Replit Secrets before using
    any database-backed endpoint.
    """
    if not settings.SUPABASE_URL or not settings.SUPABASE_SERVICE_KEY:
        raise RuntimeError(
            "Supabase credentials are not configured. "
            "Set SUPABASE_URL and SUPABASE_SERVICE_KEY as Replit Secrets "
            "and restart the workflow."
        )
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


# Lazy accessor — do NOT call get_supabase_client() at module level.
# Import and call get_supabase_client() only inside request handlers or
# repository methods so the server can start without Supabase credentials.
def get_supabase() -> Client:
    """Convenience alias; raises RuntimeError if credentials are missing."""
    return get_supabase_client()


