"""
Authentication dependency (Presentation layer).

Verifies the Supabase-issued access token sent by the Flutter client on
every request (`Authorization: Bearer <token>`), and exposes the
authenticated user's id to routers via `get_current_user_id`.

WHY THIS EXISTS: without it, every endpoint took `user_id` straight from
the URL path or request body with no proof the caller actually owned that
account. Anyone who could see or guess a UUID could read or write another
user's balance, goals, and transactions. This closes that gap.

TWO SUPABASE SIGNING SCHEMES: older Supabase projects sign access tokens
with a single shared secret (HS256) -- that's `settings.SUPABASE_JWT_SECRET`.
Newer projects default to asymmetric "JWT Signing Keys" (ES256/RS256)
instead, published at the project's JWKS endpoint, and verifying those
requires fetching the matching public key rather than a shared secret.
A deployment only ever uses one scheme, but this module can't know which
without asking the project itself, so `get_current_user_id` tries the
cheap, no-network HS256 path first and only falls back to the JWKS lookup
if that fails -- correct (and fast) for either kind of project without
any extra configuration.
"""

from __future__ import annotations

from functools import lru_cache

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

# Newer Supabase projects publish their asymmetric verification keys here.
_JWKS_URL_SUFFIX = "/auth/v1/.well-known/jwks.json"


@lru_cache
def _get_jwks_client() -> jwt.PyJWKClient:
    """
    Returns a cached `PyJWKClient` pointed at this Supabase project's JWKS
    endpoint. Cached (not re-created per request) since `PyJWKClient`
    itself caches the fetched keys internally and is safe to reuse -- one
    instance for the process's lifetime avoids re-fetching the JWKS on
    every single request.
    """
    return jwt.PyJWKClient(f"{settings.SUPABASE_URL}{_JWKS_URL_SUFFIX}")


def _decode_with_shared_secret(token: str) -> dict | None:
    """Legacy path: HS256, verified against the project's shared JWT secret. Returns None (never raises) on any failure so the caller can fall back."""
    try:
        return jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except jwt.PyJWTError:
        return None


def _decode_with_jwks(token: str) -> dict | None:
    """Newer path: asymmetric signing keys, fetched (and cached) from the project's JWKS endpoint. Returns None (never raises) on any failure."""
    try:
        signing_key = _get_jwks_client().get_signing_key_from_jwt(token)
        return jwt.decode(
            token,
            signing_key.key,
            algorithms=["ES256", "RS256"],
            audience="authenticated",
        )
    except (jwt.PyJWTError, jwt.PyJWKClientError):
        return None


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

    token = credentials.credentials
    payload = _decode_with_shared_secret(token) or _decode_with_jwks(token)

    if payload is None:
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