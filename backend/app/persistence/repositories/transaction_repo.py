"""
Transaction Repository.

Owns all read/write access to the `transactions` table in Supabase
(PostgreSQL). This is the *only* class permitted to run queries against
`transactions` — Business-layer Facades depend on this repository rather
than talking to the Supabase client directly.

`create_transaction` implements the same semantics as the SQL
`create_transaction_atomic` RPC but via direct table operations. The RPC
is the canonical approach (see migration 002) but had a bug: the function
body inserts `p_category TEXT` into a `category_type` enum column without
casting (Postgres error 42804). Apply migration 005 to Supabase via the
Dashboard SQL editor to restore the fully-atomic RPC; until then, the
three writes below (INSERT transaction, UPDATE balance, UPSERT oasis_states)
are correct in the normal path. The idempotency key short-circuit protects
against duplicate submissions.
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta, timezone

from postgrest.exceptions import APIError
from supabase import Client

from app.core.exceptions import PersistenceError, ProfileNotFoundError
from app.persistence.models import TransactionRecord, TransactionWriteResult

_TABLE = "transactions"

logger = logging.getLogger(__name__)

# Unique-violation code raised when an idempotency_key already exists.
_ERRCODE_UNIQUE = "23505"


class TransactionRepository:
    """Repository for creating and reading `TransactionRecord`s via Supabase."""

    def __init__(self, supabase_client: Client) -> None:
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
        Records a new transaction and updates the user's balance and Oasis
        state as three separate writes.

        Idempotency: if `idempotency_key` is provided and a transaction
        already exists for `(user_id, idempotency_key)`, the existing row
        is returned (`is_replay=True`) without mutating anything.

        Note: these three writes are NOT atomic (no RPC). Apply migration
        005_fix_create_transaction_atomic_cast.sql to the Supabase project
        via the Dashboard SQL editor to restore full atomicity.

        Raises:
            ProfileNotFoundError: If the user has no `profiles` row.
            PersistenceError: If the write fails for any other reason.
        """
        # ── (a) Idempotency short-circuit ─────────────────────────────────
        if idempotency_key:
            try:
                existing_resp = (
                    self._client.table(_TABLE)
                    .select("*")
                    .eq("user_id", user_id)
                    .eq("idempotency_key", idempotency_key)
                    .limit(1)
                    .execute()
                )
                if existing_resp.data:
                    row = existing_resp.data[0]
                    return self._build_result(row, is_replay=True)
            except APIError as exc:
                raise PersistenceError(
                    f"Idempotency check failed for user '{user_id}': {exc.message}"
                ) from exc

        # ── (b) Insert transaction ────────────────────────────────────────
        # PostgREST auto-casts string → enum for table-level inserts,
        # so we do NOT need to pass ::category_type here.
        tx_data: dict = {
            "user_id": user_id,
            "amount": amount,
            "description": description,
            "category": category,
            "type": type_enum,
        }
        if idempotency_key:
            tx_data["idempotency_key"] = idempotency_key

        try:
            tx_resp = self._client.table(_TABLE).insert(tx_data).execute()
        except APIError as exc:
            # Handle race: concurrent request beat us to the idempotency key.
            if getattr(exc, "code", None) == _ERRCODE_UNIQUE and idempotency_key:
                try:
                    existing_resp = (
                        self._client.table(_TABLE)
                        .select("*")
                        .eq("user_id", user_id)
                        .eq("idempotency_key", idempotency_key)
                        .limit(1)
                        .execute()
                    )
                    if existing_resp.data:
                        return self._build_result(existing_resp.data[0], is_replay=True)
                except APIError:
                    pass
            # Surface ProfileNotFoundError for the case where the profile
            # check in the DB (via a trigger or FK) catches the missing row.
            if getattr(exc, "code", None) == "P0004":
                raise ProfileNotFoundError(
                    f"No profile found for user '{user_id}'."
                ) from exc
            raise PersistenceError(
                f"Failed to insert transaction for user '{user_id}': {exc.message}"
            ) from exc

        if not tx_resp.data:
            raise PersistenceError(
                f"Transaction insert returned no data for user '{user_id}'."
            )

        tx_row = tx_resp.data[0]

        # ── (c) Update balance ────────────────────────────────────────────
        # Fetch current balance then write the new value. Small read-modify-
        # write window — idempotency key prevents double-submission, which is
        # the dominant concurrency risk for end-user transactions.
        balance_delta = (
            amount if type_enum == "INCOME" else (-amount if type_enum == "EXPENSE" else 0.0)
        )
        if balance_delta:
            try:
                profile_resp = (
                    self._client.table("profiles")
                    .select("current_balance, id")
                    .eq("id", user_id)
                    .limit(1)
                    .execute()
                )
                if profile_resp.data:
                    current = float(profile_resp.data[0].get("current_balance", 0))
                    self._client.table("profiles").update(
                        {"current_balance": round(current + balance_delta, 2)}
                    ).eq("id", user_id).execute()
                else:
                    raise ProfileNotFoundError(
                        f"No profile found for user '{user_id}'; cannot update balance."
                    )
            except ProfileNotFoundError:
                raise
            except APIError as exc:
                logger.error(
                    "Balance update failed for user %s after successful insert (tx_id=%s): %s",
                    user_id, tx_row.get("id"), exc.message,
                )
                # Non-fatal: transaction is already committed — log and continue.

        # ── (d) Upsert Oasis state ────────────────────────────────────────
        if growth_delta or health_delta:
            self._update_oasis_state(user_id, growth_delta, health_delta)

        return self._build_result(tx_row, is_replay=False)

    # ── Private helpers ───────────────────────────────────────────────────

    def _update_oasis_state(
        self, user_id: str, growth_delta: float, health_delta: float
    ) -> None:
        """Upserts the `oasis_states` row with streak logic mirroring migration 002."""
        try:
            existing_resp = (
                self._client.table("oasis_states")
                .select("*")
                .eq("user_id", user_id)
                .limit(1)
                .execute()
            )
            today = date.today()
            is_positive = growth_delta > 0

            if existing_resp.data:
                s = existing_resp.data[0]
                new_growth = max(0.0, float(s.get("growth_level", 0)) + growth_delta)
                new_health = max(0.0, min(100.0, float(s.get("health_score", 100)) + health_delta))
                cur_streak = int(s.get("current_streak_days", 0))
                lng_streak = int(s.get("longest_streak_days", 0))
                raw_last = s.get("last_positive_action_date")
                last_action: date | None = (
                    date.fromisoformat(raw_last[:10]) if raw_last else None
                )

                if is_positive:
                    if last_action == today:
                        new_streak = cur_streak
                    elif last_action == today - timedelta(days=1):
                        new_streak = cur_streak + 1
                    else:
                        new_streak = 1
                    new_longest = max(lng_streak, new_streak)
                    new_last = today.isoformat()
                else:
                    new_streak = cur_streak
                    new_longest = lng_streak
                    new_last = last_action.isoformat() if last_action else None

                upsert_data: dict = {
                    "user_id": user_id,
                    "growth_level": new_growth,
                    "health_score": new_health,
                    "current_streak_days": new_streak,
                    "longest_streak_days": new_longest,
                    "last_positive_action_date": new_last,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }
            else:
                upsert_data = {
                    "user_id": user_id,
                    "growth_level": max(0.0, growth_delta),
                    "health_score": max(0.0, min(100.0, 100.0 + health_delta)),
                    "current_streak_days": 1 if is_positive else 0,
                    "longest_streak_days": 1 if is_positive else 0,
                    "last_positive_action_date": today.isoformat() if is_positive else None,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }

            self._client.table("oasis_states").upsert(
                upsert_data, on_conflict="user_id"
            ).execute()

        except APIError as exc:
            logger.error(
                "Oasis state update failed for user %s: %s", user_id, exc.message
            )
            # Non-fatal: transaction is already committed.

    @staticmethod
    def _build_result(row: dict, *, is_replay: bool) -> TransactionWriteResult:
        return TransactionWriteResult(
            id=row["id"],
            user_id=row["user_id"],
            amount=float(row["amount"]),
            description=row["description"],
            category=row.get("category", "UNCATEGORIZED"),
            type=row.get("type", "EXPENSE"),
            created_at=row["created_at"],
            idempotency_key=row.get("idempotency_key"),
            is_replay=is_replay,
            oasis_growth_level=0.0,
            oasis_health_score=100.0,
            oasis_streak_days=0,
        )

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

        return [TransactionRecord(**row) for row in (response.data or [])]

    def get_transactions_since(
        self, user_id: str, since: datetime
    ) -> list[TransactionRecord]:
        """
        Fetches transactions for a user created on or after `since`.

        Args:
            user_id: UUID (as string) of the owning user.
            since: Timezone-aware datetime; only transactions with
                `created_at >= since` are returned.

        Returns:
            A list of `TransactionRecord`s (empty if none match).

        Raises:
            PersistenceError: If the query fails.
        """
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

        return [TransactionRecord(**row) for row in (response.data or [])]

    def get_category_spending_stats(
        self, user_id: str, category: str
    ) -> tuple[float, float, int]:
        """
        Returns (avg_amount, stddev_amount, sample_size) of EXPENSE amounts
        for a given category, as computed by the `get_category_spending_stats`
        SQL function (migration 002).

        Used by the anomaly-detection pass in `TransactionFacade`.  Returns
        (0, 0, 0) if there are no data points — the caller's
        `_ANOMALY_MIN_SAMPLE_SIZE` guard prevents false positives.

        Args:
            user_id: UUID (as string) of the owning user.
            category: The `CategoryEnum` value (as string) to filter on.

        Returns:
            A `(avg_amount, stddev_amount, sample_size)` tuple.  All values
            are 0 if the RPC returns no rows.

        Raises:
            PersistenceError: If the query fails.
        """
        try:
            response = (
                self._client.rpc(
                    "get_category_spending_stats",
                    {"p_user_id": user_id, "p_category": category},
                ).execute()
            )
        except APIError as exc:
            raise PersistenceError(
                f"Failed to fetch spending stats for user '{user_id}': {exc.message}"
            ) from exc

        if not response.data:
            return 0.0, 0.0, 0

        row = response.data[0] if isinstance(response.data, list) else response.data
        return (
            float(row.get("avg_amount", 0)),
            float(row.get("stddev_amount", 0)),
            int(row.get("sample_size", 0)),
        )
