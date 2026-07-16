"""
Profile Repository.

Owns read access to the `profiles` table in Supabase (PostgreSQL) needed
outside the transaction-write path — currently just fetching
`current_balance` for the unified dashboard summary. Writes to
`profiles.current_balance` only ever happen inside `create_transaction_atomic`
(see `TransactionRepository`), so this repository is read-only.
"""

from __future__ import annotations

from postgrest.exceptions import APIError
from supabase import Client

from app.core.exceptions import PersistenceError, ProfileNotFoundError
from app.persistence.models import ProfileRecord

_TABLE = "profiles"


class ProfileRepository:
    """Repository for reading `ProfileRecord`s via Supabase."""

    def __init__(self, supabase_client: Client) -> None:
        """
        Args:
            supabase_client: A configured Supabase `Client` instance,
                typically the process-wide singleton from
                `app.core.supabase_client`, injected here for testability.
        """
        self._client = supabase_client

    def get_profile(self, user_id: str) -> ProfileRecord:
        """
        Fetches a user's profile.

        Args:
            user_id: UUID (as string) of the user.

        Returns:
            The `ProfileRecord`.

        Raises:
            ProfileNotFoundError: If no `profiles` row matches `user_id`.
            PersistenceError: If the query fails for any other reason.
        """
        try:
            response = (
                self._client.table(_TABLE)
                .select("*")
                .eq("id", user_id)
                .limit(1)
                .execute()
            )
        except APIError as exc:
            raise PersistenceError(
                f"Failed to fetch profile for user '{user_id}': {exc.message}"
            ) from exc

        if not response.data:
            raise ProfileNotFoundError(f"No profile found for user '{user_id}'.")

        return ProfileRecord(**response.data[0])
