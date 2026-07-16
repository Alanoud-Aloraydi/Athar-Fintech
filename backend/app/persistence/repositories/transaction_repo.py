"""
Transaction Repository.

Owns all read/write access to the `transactions` table in Supabase
(PostgreSQL). This is the *only* class permitted to run queries against
`transactions` — Business-layer Facades depend on this repository rather
than talking to the Supabase client directly.

`create_transaction` calls a Postgres function (`create_transaction_atomic`
— see `supabase/migrations/002_oasis_gamification_and_idempotency.sql`)
rather than issuing a raw `insert` directly. Recording a transaction,
updating `profiles.current_balance`, and updating the user's persisted
Oasis running totals are three writes that must commit together and must
not lose a race under concurrent transactions for the same user — the same
class of problem `increment_goal_progress` solves for goals, solved the
same way: push the read-modify-write into a single atomic statement in the
database instead of separate round-trips from Python. The same RPC also
handles idempotent replay (see `create_transaction`'s docstring).
"""

from __future__ import annotations

from datetime import datetime, timezone

from postgrest.exceptions import APIError
from supabase import Client

from app.core.exceptions import PersistenceError, ProfileNotFoundError
from app.persistence.models import TransactionRecord, TransactionWriteResult

_TABLE = "transactions"

# Postgres error code raised by create_transaction_atomic (see the SQL
# migration) when the user_id has no matching profiles row.
_ERRCODE_PROFILE_NOT_FOUND = "P0004"


class TransactionRepository:
    """Repository for creating and reading `TransactionRecord`s via Supabase."""

    def __init__(self, supabase_client: Client) -> None:
        """
        Args:
            supabase_client: A configured Supabase `Client` instance,
                typically the process-wide singleton from
                `app.core.supabase_client`, injected here for testability.
        """
        self._client = supabase_client

    def create_transaction(
        self,
        user_id: str,
        amount: float,
        description: str,
        category: str,
        type_enum: str,
        idempotency_key: str | None = None,
        growth_delta: float = 0.0,
        health_delta: float = 0.0,
    ) -> TransactionWriteResult:
        """
        Atomically inserts a new transaction row, updates the owning user's
        `profiles.current_balance`, AND updates their persisted Oasis
        running totals — all in the same database operation (see
        `create_transaction_atomic` in the SQL migration).

        Idempotency: if `idempotency_key` is provided and a transaction
        already exists for `(user_id, idempotency_key)`, the RPC returns
        that existing row (with `is_replay=True`) instead of inserting a
        duplicate or mutating the balance/Oasis state a second time — this
        is what makes it safe for the Flutter client to retry a
        `POST /transactions/` call after a dropped response without
        double-charging the user.

        Args:
            user_id: UUID (as string) of the owning user.
            amount: The transaction amount.
            description: Raw merchant/transaction description.
            category: The `CategoryEnum` value (as string) assigned by the
                Categorization Engine.
            type_enum: Either "EXPENSE" or "INCOME".
            idempotency_key: Optional client-generated key (e.g. a UUID)
                identifying this logical request, unique per user. Pass
                `None` to skip idempotency checking entirely (the write
                always proceeds as a fresh insert).
            growth_delta: The Oasis growth delta computed by the
                Gamification Engine for this transaction, folded into
                `oasis_states.growth_level` atomically.
            health_delta: Same, for `oasis_states.health_score`.

        Returns:
            A `TransactionWriteResult` — the persisted (or replayed)
            transaction plus the resulting Oasis snapshot.

        Raises:
            ProfileNotFoundError: If `user_id` has no matching `profiles`
                row. Should be unreachable in normal operation — every
                signup auto-provisions a profile — so this indicates a
                genuine data-integrity anomaly rather than a routine
                business-rule rejection.
            PersistenceError: If the RPC call fails for any other
                reason, or returns no data.
        """
        try:
            response = self._client.rpc(
                "create_transaction_atomic",
                {
                    "p_user_id": user_id,
                    "p_amount": amount,
                    "p_description": description,
                    "p_category": category,
                    "p_type": type_enum,
                    "p_idempotency_key": idempotency_key,
                    "p_growth_delta": growth_delta,
                    "p_health_delta": health_delta,
                },
            ).execute()
        except APIError as exc:
            if getattr(exc, "code", None) == _ERRCODE_PROFILE_NOT_FOUND:
                raise ProfileNotFoundError(
                    f"No profile found for user '{user_id}'; cannot record transaction."
                ) from exc
            raise PersistenceError(
                f"Failed to insert transaction for user '{user_id}': {exc.message}"
            ) from exc

        if not response.data:
            raise PersistenceError(
                f"create_transaction_atomic returned no data for user '{user_id}'."
            )

        row = response.data[0] if isinstance(response.data, list) else response.data
        return TransactionWriteResult(**row)

    def get_transactions_for_user(self, user_id: str) -> list[TransactionRecord]:
        """
        Fetches all transactions belonging to a user, most recent first.

        Args:
            user_id: UUID (as string) of the owning user.

        Returns:
            A list of `TransactionRecord`s (empty if the user has none).

        Raises:
            PersistenceError: If the query fails.
        """
        try:
            response = (
                self._client.table(_TABLE)
                .select("*")
                .eq("user_id", user_id)
                .order("created_at", desc=True)
                .execute()
            )
        except APIError as exc:
            raise PersistenceError(
                f"Failed to fetch transactions for user '{user_id}': {exc.message}"
            ) from exc

        return [TransactionRecord(**row) for row in response.data]

    def get_transactions_since(
        self, user_id: str, since: datetime
    ) -> list[TransactionRecord]:
        """
        Fetches transactions for a user created at or after `since`.

        Used for windowed calculations (spending velocity, savings rate)
        that only need a recent slice of history rather than the full
        transaction log — a narrower, indexed range scan instead of
        `get_transactions_for_user`'s full-history fetch.

        Args:
            user_id: UUID (as string) of the owning user.
            since: Inclusive lower bound on `created_at`. Pass a
                timezone-aware `datetime`.

        Returns:
            A list of `TransactionRecord`s created at or after `since`.

        Raises:
            PersistenceError: If the query fails.
        """
        if since.tzinfo is None:
            since = since.replace(tzinfo=timezone.utc)

        try:
            response = (
                self._client.table(_TABLE)
                .select("*")
                .eq("user_id", user_id)
                .gte("created_at", since.isoformat())
                .order("created_at", desc=True)
                .execute()
            )
        except APIError as exc:
            raise PersistenceError(
                f"Failed to fetch recent transactions for user '{user_id}': {exc.message}"
            ) from exc

        return [TransactionRecord(**row) for row in response.data]

    def get_category_spending_stats(
        self, user_id: str, category: str
    ) -> tuple[float, float, int]:
        """
        Returns `(avg_amount, stddev_amount, sample_size)` for a user's past
        EXPENSE transactions in a given category, computed server-side by
        `get_category_spending_stats` (see the SQL migration) rather than
        by pulling their transaction history into Python — backs the
        spend-anomaly flag on new transactions.

        Args:
            user_id: UUID (as string) of the owning user.
            category: The `CategoryEnum` value (as string) to compute stats for.

        Returns:
            `(0.0, 0.0, 0)` if the user has no prior EXPENSE transactions
            in this category.

        Raises:
            PersistenceError: If the RPC call fails.
        """
        try:
            response = self._client.rpc(
                "get_category_spending_stats",
                {"p_user_id": user_id, "p_category": category},
            ).execute()
        except APIError as exc:
            raise PersistenceError(
                f"Failed to fetch category spending stats for user '{user_id}': {exc.message}"
            ) from exc

        if not response.data:
            return 0.0, 0.0, 0

        row = response.data[0] if isinstance(response.data, list) else response.data
        return (
            float(row.get("avg_amount", 0.0)),
            float(row.get("stddev_amount", 0.0)),
            int(row.get("sample_size", 0)),
        )
