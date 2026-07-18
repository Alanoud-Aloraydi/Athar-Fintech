# Athar FinTech (أَثر)

A bilingual (Arabic/English) FinTech demo app that turns spending habits into a living 3D Palm Tree Oasis. Healthy finances grow the Oasis to 9 palms; reckless spending causes it to wither.

## Stack

| Layer | Technology |
|-------|-----------|
| Backend | FastAPI (Python 3.12), Uvicorn |
| Frontend | Flutter Web |
| Database | Supabase (PostgreSQL) |
| Auth | Supabase Auth + PyJWT (ES256) |
| 3D Engine | Spline (assets vendored locally — no CDN) |

## Project Structure

```
.
├── athar_frontend/               # Flutter Web app
│   ├── lib/
│   │   ├── config/env.dart       # API_BASE_URL, SUPABASE_URL/KEY (--dart-define)
│   │   ├── models/models.dart    # All DTOs (DashboardSummary, Goal, Transaction …)
│   │   ├── services/             # api_service.dart + auth_service.dart
│   │   ├── screens/              # dashboard, farm (Oasis), transactions, profile, login
│   │   └── widgets/              # palm_oasis_viewer, oasis_iframe_web, common_widgets
│   ├── assets/oasis/             # runtime.js + scene.splinecode + *.wasm (all vendored)
│   └── test/
│
├── backend/
│   └── app/
│       ├── core/                 # config.py (pydantic-settings), security.py (ES256 JWT)
│       ├── business/
│       │   ├── facades/          # analytics, goal (+ cancel_goal), oasis, transaction
│       │   ├── categorization/   # models.py (10-cat enum) + bilingual regex engine
│       │   └── gamification/     # health score + streak rules
│       ├── persistence/
│       │   └── repositories/     # goal_repo.py, transaction_repo.py
│       └── presentation/
│           ├── routers/          # analytics, goals, oasis, transactions
│           ├── schemas/          # DTOs: DashboardSummaryDTO, GoalProgressDTO, …
│           └── dependencies.py   # FastAPI DI wiring
│   ├── supabase/migrations/      # 000–005 SQL migrations
│   └── requirements.txt
│
├── scripts/
└── start.sh                      # Single entry: pip install → flutter build → uvicorn :5000
```

## How to Run

Click **Run** — `start.sh` does everything:

1. `pip install -r requirements.txt`
2. `flutter pub get` + build web (hash-cached, skips if source unchanged)
3. `uvicorn` on **port 5000** — serves both the Flutter web app AND the FastAPI

| URL | Content |
|-----|---------|
| `/` | Flutter web app (main preview pane) |
| `/docs` | Swagger UI |

> There is **no separate port for the backend**. FastAPI on 5000 serves the compiled Flutter build as static files AND the API at `/analytics`, `/goals`, `/oasis`, `/transactions`.

## Environment Variables / Secrets

All secrets live in **Replit Secrets** (never in `.env`). `start.sh` injects `API_BASE_URL` and `CORS_ORIGINS` automatically at build time.

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Service role key (backend — bypasses RLS) |
| `SUPABASE_JWT_SECRET` | ES256 public key for PyJWT token verification |
| `SUPABASE_ANON_KEY` | Anon/public key (Flutter Supabase client) |
| `SESSION_SECRET` | Random secret for session signing |

## Financial Model (Two-Ledger)

| Ledger | Formula |
|--------|---------|
| Current Account | `Baseline (8,500 SAR) + Σ income − Σ expenses` |
| Savings Wallet | `Baseline (15,000 SAR) + active_goal.saved_amount` |

- Goal progress always uses `savings_wallet_balance / target` (not raw DB `saved_amount`).
- `DashboardSummaryDTO` is the **single source of truth** for the Oasis tab — `farm_screen.dart` calls `getDashboardSummary()` (same as the Dashboard) to keep both tabs in sync.

## Goal Lifecycle

| Status | Trigger | Effect |
|--------|---------|--------|
| `COMPLETED` | Wallet ≥ target | Archived to history, wallet balance kept |
| `CANCELLED` | User cancels | Saved amount refunded as INCOME to current account; Oasis resets |
| `ARCHIVED` | Legacy alias | Same as COMPLETED |

## 10 Spending Categories

`FOOD` · `GROCERIES` · `UTILITIES` · `ENTERTAINMENT` · `HEALTH` · `TRANSPORT` · `HOUSING` · `SHOPPING` · `SAVINGS` · `UNCATEGORIZED`

Defined in `backend/app/business/categorization/models.py` — single source of truth for both backend and Flutter (`AppCategory` enum in `models.dart`).

## CORS

`start.sh` sets `CORS_ORIGINS` to the live Replit dev domain at startup. FastAPI guards against the `allow_credentials=True` + wildcard origin crash — see `backend/app/main.py`.

## User Preferences

- Keep existing project structure (`athar_frontend/` for Flutter, `backend/` for FastAPI)
- Do not migrate the database away from Supabase
- `withOpacity` → `withValues(alpha:)` convention throughout Flutter code
