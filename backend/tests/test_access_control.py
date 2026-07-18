"""
Access-control tests — defense-in-depth verification.

These tests prove that cross-user data access is blocked at BOTH layers:

  Layer 1 — Application:  `require_matching_user` in each route handler.
  Layer 2 — Dependency:   `get_user_scoped_client` / `get_current_user_id` in
                           `dependencies.py` and `auth.py` reject requests
                           without a valid Bearer token, and the per-user
                           Supabase client is used for all repository calls
                           (so the DB's RLS policies are enforced).

Why a mock-based test rather than a live Supabase round-trip
-------------------------------------------------------------
A true end-to-end test (two real Supabase accounts, live JWT) requires
credentials that cannot be present in CI without secrets.  Instead, these
tests mock `create_client` so no real network connections are made, then
verify that:
  a) missing/invalid tokens always return HTTP 401 before any DB call,
  b) a valid token for User A is rejected with HTTP 403 when the path
     references User B's ID,
  c) `get_user_scoped_client` (the dependency that wires the per-user
     Supabase client into repositories) raises HTTP 401 if no Bearer header
     is present — proving the DB-layer client can never be created without a
     JWT, which is what makes RLS enforcement possible,
  d) `get_user_supabase_client` calls `client.postgrest.auth(token)` on the
     client it returns, ensuring every PostgREST request carries the user's
     JWT and the DB can enforce RLS policies.

Run with:  cd backend && python -m pytest tests/test_access_control.py -v
"""

from __future__ import annotations

import uuid
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

# ---------------------------------------------------------------------------
# Test constants
# ---------------------------------------------------------------------------

_FAKE_URL = "https://fake.supabase.co"
_FAKE_ANON = "fake-anon-key"
_FAKE_SERVICE = "fake-service-key"
# Must be ≥ 32 chars so HS256 JWT signing doesn't complain.
_FAKE_JWT_SECRET = "fake-jwt-secret-at-least-32-chars-long!!"

USER_A = str(uuid.uuid4())
USER_B = str(uuid.uuid4())


def _make_jwt_for(user_id: str) -> str:
    """Creates a minimal HS256-signed Supabase-style JWT for `user_id`."""
    import jwt as pyjwt

    return pyjwt.encode(
        {"sub": user_id, "aud": "authenticated", "role": "authenticated"},
        _FAKE_JWT_SECRET,
        algorithm="HS256",
    )


def _mock_settings_for_supabase_client() -> MagicMock:
    """Returns a MagicMock that satisfies the credential checks in supabase_client.py."""
    s = MagicMock()
    s.SUPABASE_URL = _FAKE_URL
    s.SUPABASE_ANON_KEY = _FAKE_ANON
    s.SUPABASE_SERVICE_KEY = _FAKE_SERVICE
    return s


def _mock_settings_for_auth() -> MagicMock:
    """Returns a MagicMock that satisfies the JWT-verification checks in auth.py."""
    s = MagicMock()
    s.SUPABASE_JWT_SECRET = _FAKE_JWT_SECRET
    s.SUPABASE_URL = _FAKE_URL
    return s


# ---------------------------------------------------------------------------
# HTTP test client fixture
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def client():
    """
    FastAPI TestClient with all Supabase I/O mocked out.

    Strategy:
    - Patch `settings` in both `supabase_client` and `auth` modules so
      credential checks and JWT verification use fake values.
    - Patch `create_client` at its point of use so no real Supabase
      network connections are made.  The real `get_user_supabase_client`
      and `get_supabase_client` functions still execute — only the
      underlying `create_client` call is short-circuited.  This is
      important: it means `postgrest.auth(token)` is still called on the
      mock client (tested separately below).
    """
    mock_sc_settings = _mock_settings_for_supabase_client()
    mock_auth_settings = _mock_settings_for_auth()

    with (
        # Replace the settings objects in the two modules that use them.
        patch("app.core.supabase_client.settings", mock_sc_settings),
        patch("app.presentation.auth.settings", mock_auth_settings),
        # Prevent real Supabase client creation.
        patch("app.core.supabase_client.create_client", return_value=MagicMock()),
    ):
        from app.main import app  # noqa: PLC0415 — must import after patches

        with TestClient(app, raise_server_exceptions=False) as c:
            yield c


# ===========================================================================
# Layer 1: missing / invalid token → 401 before any route logic runs
# ===========================================================================


class TestUnauthenticatedRequestsAreRejected:
    """Every protected endpoint must return 401 with no token."""

    def test_transactions_get_no_auth(self, client):
        r = client.get(f"/transactions/{USER_A}")
        assert r.status_code == 401, r.text

    def test_goals_get_no_auth(self, client):
        r = client.get(f"/goals/{USER_A}/active")
        assert r.status_code == 401, r.text

    def test_analytics_get_no_auth(self, client):
        r = client.get(f"/analytics/{USER_A}")
        assert r.status_code == 401, r.text

    def test_oasis_get_no_auth(self, client):
        r = client.get(f"/oasis/{USER_A}")
        assert r.status_code == 401, r.text

    def test_transactions_post_no_auth(self, client):
        r = client.post("/transactions/", json={})
        assert r.status_code == 401, r.text

    def test_goals_post_no_auth(self, client):
        r = client.post(f"/goals/{USER_A}", json={})
        assert r.status_code == 401, r.text

    def test_invalid_bearer_token_returns_401(self, client):
        r = client.get(
            f"/transactions/{USER_A}",
            headers={"Authorization": "Bearer not.a.valid.jwt"},
        )
        assert r.status_code == 401, r.text

    def test_wrong_scheme_returns_401(self, client):
        r = client.get(
            f"/transactions/{USER_A}",
            headers={"Authorization": "Basic dXNlcjpwYXNz"},
        )
        assert r.status_code == 401, r.text


# ===========================================================================
# Layer 2: valid token for User A, path targets User B → 403
# ===========================================================================


class TestCrossUserAccessIsRejected:
    """
    Authenticated as User A, any request targeting User B's resources must
    return 403 — even with a cryptographically valid JWT.

    These tests exercise `require_matching_user`, which is the FIRST
    application-layer ownership guard.  The second layer (DB-level RLS via
    the per-user Supabase client) is exercised separately below.
    """

    def _auth(self) -> dict:
        return {"Authorization": f"Bearer {_make_jwt_for(USER_A)}"}

    def test_get_transactions_of_other_user(self, client):
        r = client.get(f"/transactions/{USER_B}", headers=self._auth())
        assert r.status_code == 403, r.text

    def test_get_goals_of_other_user(self, client):
        r = client.get(f"/goals/{USER_B}/active", headers=self._auth())
        assert r.status_code == 403, r.text

    def test_get_analytics_of_other_user(self, client):
        r = client.get(f"/analytics/{USER_B}", headers=self._auth())
        assert r.status_code == 403, r.text

    def test_get_oasis_of_other_user(self, client):
        r = client.get(f"/oasis/{USER_B}", headers=self._auth())
        assert r.status_code == 403, r.text

    def test_create_goal_for_other_user(self, client):
        r = client.post(
            f"/goals/{USER_B}",
            json={"title": "Steal Goal", "target_amount": 500, "category": "SAVINGS"},
            headers=self._auth(),
        )
        assert r.status_code == 403, r.text

    def test_patch_goal_status_of_other_user(self, client):
        fake_goal_id = str(uuid.uuid4())
        r = client.patch(
            f"/goals/{USER_B}/{fake_goal_id}/status",
            json={"status": "ARCHIVED"},
            headers=self._auth(),
        )
        assert r.status_code == 403, r.text

    def test_post_transaction_for_other_user(self, client):
        """Body contains user_id = USER_B but token is for USER_A."""
        payload = {
            "user_id": USER_B,
            "amount": 100.0,
            "description": "Cross-user inject",
            "type_enum": "EXPENSE",
        }
        r = client.post("/transactions/", json=payload, headers=self._auth())
        assert r.status_code == 403, r.text

    def test_simulate_oasis_for_other_user(self, client):
        r = client.post(
            f"/oasis/{USER_B}/simulate",
            # `type` alias is required by OasisSimulationRequestDTO
            json={"amount": 100.0, "description": "Test", "type": "EXPENSE"},
            headers=self._auth(),
        )
        assert r.status_code == 403, r.text


# ===========================================================================
# Unit tests: dependency wiring and per-user client construction
# These tests do NOT use the module-scoped `client` fixture so they have
# full control over what is patched.
# ===========================================================================


class TestUserScopedClientDependency:
    """
    Verify that `get_user_scoped_client` (the FastAPI dependency that builds
    the per-user Supabase client) correctly:
      - raises HTTP 401 when no Bearer token is present, and
      - calls `get_user_supabase_client(token)` with the raw token string.
    """

    def test_dependency_raises_401_without_credentials(self):
        """
        Call `get_user_scoped_client` directly with credentials=None and
        verify it raises the 401 HTTPException.
        """
        from fastapi import HTTPException

        from app.presentation.dependencies import get_user_scoped_client

        with pytest.raises(HTTPException) as exc_info:
            get_user_scoped_client(credentials=None)

        assert exc_info.value.status_code == 401

    def test_dependency_passes_raw_token_to_client_factory(self):
        """
        `get_user_scoped_client` must forward the raw JWT string to
        `get_user_supabase_client` so the returned client has the correct
        Authorization header attached for PostgREST/RLS.
        """
        from fastapi.security import HTTPAuthorizationCredentials

        # Import the dependency module so we can patch the name it bound at
        # import time.
        import app.presentation.dependencies as deps_mod

        fake_token = "a.b.c"
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=fake_token)

        with patch.object(deps_mod, "get_user_supabase_client") as mock_factory:
            mock_factory.return_value = MagicMock()
            deps_mod.get_user_scoped_client(credentials=creds)
            mock_factory.assert_called_once_with(fake_token)


class TestUserSupabaseClientSetsAuthHeader:
    """
    Verify that `get_user_supabase_client` attaches the caller's JWT to the
    PostgREST client layer via `client.postgrest.auth(token)`.

    This is the mechanism that makes Supabase's Row Level Security policies
    enforceable: without the auth header, `auth.uid()` resolves to NULL
    inside RLS policies and the per-user policies never fire.
    """

    def test_postgrest_auth_is_called_with_token(self):
        """
        `get_user_supabase_client` must call `client.postgrest.auth(token)`
        on the Supabase client it creates, so that every PostgREST request
        carries the user's JWT and the DB can enforce RLS.
        """
        # Import the module so we can patch names within it directly.
        import app.core.supabase_client as sc_mod

        fake_token = "header.payload.signature"
        mock_client = MagicMock()
        mock_settings = _mock_settings_for_supabase_client()

        with (
            patch.object(sc_mod, "settings", mock_settings),
            patch.object(sc_mod, "create_client", return_value=mock_client),
        ):
            result = sc_mod.get_user_supabase_client(fake_token)

        # Verify the JWT was attached to the PostgREST layer of the client.
        mock_client.postgrest.auth.assert_called_once_with(fake_token)
        assert result is mock_client

    def test_missing_anon_key_raises_runtime_error(self):
        """
        `get_user_supabase_client` must raise RuntimeError (not silently
        proceed) when SUPABASE_ANON_KEY is not configured, so the server
        fails loudly rather than issuing un-authenticated queries.
        """
        import app.core.supabase_client as sc_mod

        bad_settings = MagicMock()
        bad_settings.SUPABASE_URL = _FAKE_URL
        bad_settings.SUPABASE_ANON_KEY = None  # missing

        with patch.object(sc_mod, "settings", bad_settings):
            with pytest.raises(RuntimeError, match="SUPABASE_ANON_KEY"):
                sc_mod.get_user_supabase_client("some.token.here")
