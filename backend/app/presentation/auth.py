"""
Authentication dependency (Presentation layer).

Verifies the Supabase-issued access token sent by the Flutter client on
every request (`Authorization: Bearer <token>`), and exposes the
authenticated user's id to routers via `get_current_user_id`.

WHY THIS EXISTS: without it, every endpoint took `user_id` straight from
the URL path or request body with no proof the caller actually owned that
account. Anyone who could see or guess a UUID could read or write another
user's balance, goals, and transactions. This closes that gap.
"""

from __future__ import annotations

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import settings

# `auto_error=False` so a missing header falls through to our own 401
# below with a consistent, generic message, instead of FastAPI's default
# error shape.
_bearer_scheme = HTTPBearer(auto_error=False)

# Returned for every auth failure (missing header, expired token, bad
# signature, malformed token, ...). Deliberately identical in every case
# so a caller probing the API can't distinguish "no token" from "token
# expired" from "token forged" -- that distinction is a debugging aid,
# not something to hand an attacker.
_UNAUTHORIZED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Not authenticated.",
    headers={"WWW-Authenticate": "Bearer"},
)


def get_current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> str:
    """
    Validates the Supabase access token and returns the authenticated
    user's UUID (the JWT's `sub` claim).

    Add this as a dependency on any endpoint that must be restricted to
    a logged-in caller.
    """
    if credentials is None or not credentials.credentials:
        raise _UNAUTHORIZED

    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.PyJWTError:
        raise _UNAUTHORIZED

    user_id = payload.get("sub")
    if not user_id:
        raise _UNAUTHORIZED

    return user_id


def require_matching_user(path_user_id: str, current_user_id: str) -> None:
    """
    Ensures the authenticated user (from the verified token) matches the
    `user_id` the request is trying to access. Call this at the top of
    every user-scoped endpoint, right after resolving the dependency.

    Raises 403 on mismatch. Uses the same generic detail message
    regardless of *why* it failed, so this can't be used to enumerate
    which user_ids exist.
    """
    if str(path_user_id) != str(current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this resource.",
        )