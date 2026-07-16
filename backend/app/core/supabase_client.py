
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
    """
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)


# Module-level singleton for direct imports (e.g. `from app.core.supabase_client import supabase`)
supabase: Client = get_supabase_client()


