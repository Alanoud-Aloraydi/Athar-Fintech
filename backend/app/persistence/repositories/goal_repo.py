
"""
Goal Repository.

Owns all read/write access to the `goals` table in Supabase (PostgreSQL).
This is the *only* class permitted to run queries against `goals` â€”
Business-layer Facades depend on this repository rather than talking to
the Supabase client directly.

`create_goal`, `transition_status`, and `increment_saved_amount` call
Postgres functions (see `supabase/goal_lifecycle_functions.sql`) rather
than issuing a raw `insert`/`update` directly. Each of these operations
has a business invariant that can only be enforced correctly with a
single atomic statement on the database side: "at most one ACTIVE goal
per user" and "increment saved_amount without a lost-update race under
concurrent writes" are both TOCTOU-prone if implemented as separate
read-then-write calls from Python. Pushing them into the database is
what makes them actually safe rather than just usually safe.
"""

from __future__ import annotations

from datetime import date

from postgrest.exceptions import APIError
from supabase import Client

from app.core.exceptions import GoalConflictError, GoalNotFoundError, PersistenceError
from app.persistence.models import GoalRecord

_TABLE = "goals"
_ACTIVE_STATUS = "ACTIVE"

# Postgres error codes raised by the lifecycle functions (see
# goal_lifecycle_functions.sql) or by Postgres itself, mapped to the
# domain exceptions the Business layer understands.
_ERRCODE_ACTIVE_GOAL_EXISTS = "P0001"  # raised explicitly by create_goal_atomic
_ERRCODE_UNIQUE_VIOLATION = "23505"  # Postgres native code; backstop via uq_goals_one_active_per_user
_ERRCODE_GOAL_NOT_FOUND = "P0002"  # raised by transition_goal_status / increment_goal_progress
_ERRCODE_GOAL_NOT_ACTIVE = "P0003"  # raised by transition_goal_status


class GoalRepository:
    """Repository for creating, reading, and updating `GoalRecord`s via Supabase."""

    def __init__(self, supabase_client: Client) -> None:
        """
        Args:
            supabase_client: A configured Supabase `Client` instance,
                typically the process-wide singleton from
                `app.core.supabase_client`, injected here for testability.
        """
        self._client = supabase_client

    def create_goal(
        self,
        user_id: str,
        title: str,
        target_amount: float,
        category: str,
        deadline: date | None = None,
    ) -> GoalRecord:
        """
        Atomically creates a new `ACTIVE` goal for the user, enforcing
        "at most one ACTIVE goal per user" as a single database operation
        (see `create_goal_atomic` in goal_lifecycle_functions.sql) rather
        than a separate check-then-insert from this layer.

        Args:
            user_id: UUID (as string) of the owning user.
            title: Short display name for the goal (e.g. "Emergency Fund").
            target_amount: Total amount the user wants to reach.
            category: The `CategoryEnum` value (as string) this goal is
                tied to.
            deadline: Optional target date to reach the goal by.

        Returns:
            The newly persisted `GoalRecord`, with `saved_amount`
            initialized to `0.0` and `status` set to `'ACTIVE'`.

        Raises:
            GoalConflictError: If the user already has an ACTIVE goal.
            PersistenceError: If the RPC call fails for any other reason,
                or returns no data.
        """
        try:
            response = self._client.rpc(
                "create_goal_atomic",
                {
                    "p_user_id": user_id,
                    "p_title": title,
                    "p_target_amount": target_amount,
                    "p_category": category,
                    "p_deadline": deadline.isoformat() if deadline else None,
                },
            ).execute()
        except APIError as exc:
            if getattr(exc, "code", None) in (
                _ERRCODE_ACTIVE_GOAL_EXISTS,
                _ERRCODE_UNIQUE_VIOLATION,
            ):
                raise GoalConflictError(
                    f"User '{user_id}' already has an active goal â€” "
                    "complete or archive it before creating a new one."
                ) from exc
            raise PersistenceError(
                f"Failed to insert goal for user '{user_id}': {exc.message}"
            ) from exc

        return GoalRecord(**self._unwrap_rpc_row(response.data, "create_goal_atomic", user_id))

    def get_active_goal(self, user_id: str) -> GoalRecord | None:
        """
        Fetches the user's currently active Financial Goal, if any.

        The single-ACTIVE-goal-per-user invariant is enforced at the
        database level (see `uq_goals_one_active_per_user` in
        schema.sql), so this method returning more than one row would
        indicate that invariant was violated â€” it still only returns the
        first match defensively, but that would be a bug elsewhere, not
        expected behavior.

        Args:
            user_id: UUID (as string) of the owning user.

        Returns:
            The active `GoalRecord`, or `None` if the user has no active
            goal.

        Raises:
            PersistenceError: If the query fails.
        """
        try:
            response = (
                self._client.table(_TABLE)
                .select("*")
                .eq("user_id", user_id)
                .eq("status", _ACTIVE_STATUS)
                .limit(1)
                .execute()
            )
        except APIError as exc:
            raise PersistenceError(
                f"Failed to fetch active goal for user '{user_id}': {exc.message}"
            ) from exc

        if not response.data:
            return None

        return GoalRecord(**response.data[0])

    def transition_status(self, goal_id: str, user_id: str, new_status: str) -> GoalRecord:
        """
        Transitions a goal from `ACTIVE` to a terminal status
        (`COMPLETED` or `ARCHIVED`) â€” the only sanctioned way for a goal
        to leave the ACTIVE state. Required before the user can create a
        new goal (see `create_goal`).

        Args:
            goal_id: UUID (as string) of the goal to transition.
            user_id: UUID (as string) of the goal's owner, checked
                server-side so a user cannot transition a goal they
                don't own.
            new_status: Either `"COMPLETED"` or `"ARCHIVED"`.

        Returns:
            The updated `GoalRecord`.

        Raises:
            GoalNotFoundError: If no goal with `goal_id` exists for `user_id`.
            GoalConflictError: If the goal exists but isn't currently ACTIVE.
            PersistenceError: If the RPC call fails for any other reason.
        """
        try:
            response = self._client.rpc(
                "transition_goal_status",
                {"p_goal_id": goal_id, "p_user_id": user_id, "p_new_status": new_status},
            ).execute()
        except APIError as exc:
            code = getattr(exc, "code", None)
            if code == _ERRCODE_GOAL_NOT_FOUND:
                raise GoalNotFoundError(
                    f"Goal '{goal_id}' not found for user '{user_id}'."
                ) from exc
            if code == _ERRCODE_GOAL_NOT_ACTIVE:
                raise GoalConflictError(
                    f"Goal '{goal_id}' is not ACTIVE and cannot be transitioned."
                ) from exc
            raise PersistenceError(
                f"Failed to transition goal '{goal_id}': {exc.message}"
            ) from exc

        return GoalRecord(
            **self._unwrap_rpc_row(response.data, "transition_goal_status", goal_id)
        )

    def increment_saved_amount(self, goal_id: str, amount: float) -> GoalRecord:
        """
        Atomically adds `amount` to a goal's `saved_amount` in a single
        database statement (see `increment_goal_progress` in
        goal_lifecycle_functions.sql) â€” replaces the old
        fetch-then-write `update_goal_progress` pattern, which had a
        lost-update race under concurrent transactions for the same
        goal. Auto-transitions the goal to `COMPLETED` in the same
        statement if the new total reaches `target_amount`.

        Args:
            goal_id: UUID (as string) of the goal to update.
            amount: The amount to add to `saved_amount` (not the new total).

        Returns:
            The updated `GoalRecord`.

        Raises:
            GoalNotFoundError: If no ACTIVE goal matches `goal_id` (either
                it doesn't exist, or is no longer ACTIVE â€” e.g. it was
                completed or archived concurrently).
            PersistenceError: If the RPC call fails for any other reason.
        """
        try:
            response = self._client.rpc(
                "increment_goal_progress",
                {"p_goal_id": goal_id, "p_amount": amount},
            ).execute()
        except APIError as exc:
            if getattr(exc, "code", None) == _ERRCODE_GOAL_NOT_FOUND:
                raise GoalNotFoundError(
                    f"Goal '{goal_id}' not found or is no longer ACTIVE."
                ) from exc
            raise PersistenceError(
                f"Failed to increment progress for goal '{goal_id}': {exc.message}"
            ) from exc

        return GoalRecord(
            **self._unwrap_rpc_row(response.data, "increment_goal_progress", goal_id)
        )

    def get_all_goals(self, user_id: str) -> list[GoalRecord]:
        """
        Returns all goals for a user across all statuses (ACTIVE, COMPLETED,
        ARCHIVED), ordered most-recent first. Used by the goal history
        endpoint — does NOT filter by status.

        Args:
            user_id: UUID (as string) of the owning user.

        Returns:
            A list of `GoalRecord` instances (may be empty).

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
                f"Failed to fetch goal history for user '{user_id}': {exc.message}"
            ) from exc

        return [GoalRecord(**row) for row in (response.data or [])]

    @staticmethod
    def _unwrap_rpc_row(data: object, function_name: str, context_id: str) -> dict:
        """
        Normalizes a Postgres-function RPC result to a single row dict.

        supabase-py returns a `returns <table>`-typed RPC's result as a
        list containing one dict for a single-row result; this guards
        against that shape (or a bare dict, depending on client version)
        and raises clearly if the RPC unexpectedly returned nothing.
        """
        if not data:
            raise PersistenceError(f"{function_name} returned no data for '{context_id}'.")
        return data[0] if isinstance(data, list) else data


