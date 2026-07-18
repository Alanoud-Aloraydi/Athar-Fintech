# Threat Model

## Project Overview

Athar (أَثَر) is a FinTech web application built with FastAPI (Python 3.12) as the backend and Flutter Web as the frontend, backed by Supabase (PostgreSQL) for data storage and authentication. It gamifies personal finance tracking using a 3D Palm Tree Oasis metaphor. The app is publicly deployed at `https://athar-fintech.replit.app` (autoscale, public visibility).

**Tech stack:** FastAPI + Uvicorn (port 8000 internally, 5000 externally via Flutter web served by FastAPI), Flutter Web compiled to static assets, Supabase for auth and database, PyJWT for token verification, SlowAPI for rate limiting.

**Users:** Authenticated end-users (individual consumers managing personal finances). No admin role is implemented.

## Assets

- **User financial data** — transaction history, goals, saved amounts, balance. Exposure allows unauthorized insight into financial habits.
- **Supabase service-role key** — grants full database access, bypasses Row Level Security. Compromise gives an attacker complete read/write control of all user data.
- **Supabase JWT secret / JWKS keys** — used to verify access tokens. Compromise allows token forgery.
- **Supabase anon key** — client-distributed, intended for public use; combined with RLS bypass at the backend layer, its exposure is less harmful but still noteworthy.
- **User sessions (JWT access tokens)** — issued by Supabase Auth; bearer token on every API request.

## Trust Boundaries

- **Flutter Web Client → FastAPI Backend** — All user requests cross this boundary. The backend authenticates via Supabase JWT on every protected route. The client is untrusted.
- **FastAPI Backend → Supabase** — Backend uses the service-role key, which bypasses all Row Level Security (RLS). Authorization must be enforced entirely at the application layer; there is no database-layer safety net.
- **Public vs. Authenticated** — All `/transactions`, `/goals`, `/analytics`, `/oasis` routes require `Authorization: Bearer` header. Unauthorized requests get a uniform 401.
- **Client-distributed secrets** — `SUPABASE_URL` and `SUPABASE_ANON_KEY` are embedded in the compiled Flutter web bundle via `--dart-define`. These are intentionally client-visible.

## Scan Anchors

- **Production entry points:** `backend/app/main.py` (FastAPI app), `backend/app/presentation/routers/` (transactions, goals, analytics, oasis)
- **Highest-risk areas:** `backend/app/presentation/auth.py` (JWT verification), `backend/app/presentation/dependencies.py` (Supabase client injection with service key), `backend/app/core/config.py` (ENVIRONMENT default)
- **Auth dependency:** `get_current_user_id` + `require_matching_user` in all routers — these are the sole access control gates
- **Dev-only area:** `sync_open_banking/{user_id}` is a mock endpoint that inserts synthetic data — it is included in the production build
- **Deployed URL:** `https://athar-fintech.replit.app`

## Threat Categories

### Spoofing

The backend verifies Supabase-issued JWTs using either HS256 (shared secret) or ES256/RS256 (JWKS). Both paths require `audience="authenticated"`. The `require_matching_user` guard prevents one authenticated user from accessing another user's data. The uniform 401 error on any auth failure prevents user enumeration.

**Guarantee:** Every protected endpoint MUST call both `get_current_user_id` (validates the token) and `require_matching_user` (validates ownership). Currently all four routers do this.

### Information Disclosure

- The `ENVIRONMENT` setting defaults to `"development"`, which means `/docs`, `/redoc`, and `/openapi.json` are exposed unless `ENVIRONMENT=production` is explicitly set at deployment. The live production deployment should have this set.
- Persistence-layer errors are caught and replaced with a generic message before being returned to clients; raw database errors are logged server-side only.
- The `SUPABASE_SERVICE_KEY` must not appear in logs, error responses, or the Flutter bundle — it is currently backend-only.

### Elevation of Privilege

- The Supabase client uses the **service-role key**, which bypasses all RLS. If any authorization check at the Python layer is missing or incorrect, an attacker with a valid JWT could read or write any other user's data with no database-level backstop. This is the highest-risk architectural pattern in the codebase.
- No admin role is defined. All authenticated users have equivalent access to their own data only.
- SQL injection is not applicable because the application uses the Supabase client SDK (parameterized RPC calls), not raw SQL strings.

### Denial of Service

- SlowAPI enforces a default limit of 200 requests/minute per IP. Individual sensitive endpoints do not have stricter limits.
- The `sync_open_banking` mock endpoint triggers multiple database writes per call. With a 200/min limit and no per-endpoint override, an authenticated user could generate significant write load.

### Security Misconfiguration

- `ENVIRONMENT` defaults to `"development"`, exposing API schema endpoints if not overridden in production.
- The Content Security Policy includes `'unsafe-inline'` and `'unsafe-eval'` in `script-src`, required by Flutter's compiled JavaScript bootstrap. This meaningfully weakens XSS protection.
- CORS is restricted to explicit origins (not wildcard); `start.sh` injects the Replit dev domain at startup.
