"""
Oasis Repository.

Owns all read access to the `oasis_states` table in Supabase (PostgreSQL).
Writes to this table only ever happen inside `create_transaction_atomic`
(see `TransactionRepository.create_transaction` and the SQL migration), so
this repository is read-only by design — there is no `update`/`upsert`
method here on purpose, to keep "the transaction write path is the only
writer of Oasis state" an invariant enforced by the code shape, not just
convention.
"""

from __future__ import annotations

from postgrest.exceptions import APIError
from supabase import Client

from app.core.exceptions import PersistenceError
from app.persistence.models import OasisStateRecord

_TABLE = "oasis_states"


class OasisRepository:
    """Repository for reading a user's persisted `OasisStateRecord` via Supabase."""

    def __init__(self, supabase_client: Client) -> None:
        """
        Args:
            supabase_client: A configured Supabase `Client` instance,
                typically the process-wide singleton from
                `app.core.supabase_client`, injected here for testability.
        """
        self._client = supabase_client

    def get_state(self, user_id: str) -> OasisStateRecord | None:
        """
        Fetches a user's persisted Oasis state — a single indexed row read
        on the primary key, deliberately not a replay of their transaction
        history.

        Args:
            user_id: UUID (as string) of the owning user.

        Returns:
            The `OasisStateRecord`, or `None` if the user has never had a
            transaction that touched their Oasis (e.g. a brand-new signup).
            Callers should treat `None` as the Oasis's dormant starting
            state rather than an error.

        Raises:
            PersistenceError: If the query fails.
        """
        try:
            response = (
                self._client.table(_TABLE)
                .select("*")
                .eq("user_id", user_id)
                .limit(1)
                .execute()
            )
        except APIError as exc:
            raise PersistenceError(
                f"Failed to fetch Oasis state for user '{user_id}': {exc.message}"
            ) from exc

        if not response.data:
            return None

        return OasisStateRecord(**response.data[0])
