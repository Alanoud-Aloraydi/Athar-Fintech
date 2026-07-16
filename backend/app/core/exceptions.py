
"""
Shared custom exceptions.

Defined in the Core layer so every layer (Presentation, Business,
Persistence) can import and handle the same exception types without
creating upward or circular dependencies between layers.
"""


class AtharError(Exception):
    """Base exception for all Athar-Fintech application-specific errors."""


class PersistenceError(AtharError):
    """
    Raised when a Persistence-layer operation (Supabase query, insert,
    or update) fails, or returns an unexpected/empty result.

    Repositories catch provider-specific exceptions (e.g. Postgrest's
    `APIError`) at the Persistence boundary and re-raise as
    `PersistenceError`, so the Business layer never needs to know which
    database provider is in use underneath.
    """


class GoalConflictError(AtharError):
    """
    Raised when a goal-lifecycle operation would violate a business
    invariant: creating a new goal while one is already ACTIVE, or
    transitioning a goal that isn't currently ACTIVE. Distinct from
    `PersistenceError` because this isn't an infrastructure failure â€” the
    request was well-formed and reached the database, but the operation
    is not currently allowed. Presentation maps this to HTTP 409, not 502.
    """


class GoalNotFoundError(AtharError):
    """
    Raised when a goal lookup by id (scoped to a user) matches no row â€”
    either the goal doesn't exist or doesn't belong to that user (the two
    are deliberately indistinguishable to the caller, to avoid leaking
    which goal IDs exist to a user who doesn't own them).
    """


class ProfileNotFoundError(AtharError):
    """
    Raised when `create_transaction_atomic` finds no `profiles` row for
    the given user_id. In normal operation this should be unreachable â€”
    every `auth.users` signup auto-provisions a profile via the
    `handle_new_user` trigger â€” so this surfaces a genuine data-integrity
    anomaly (e.g. a user_id that was never a real signed-up user) rather
    than an expected business-rule rejection.
    """


