# Athar FinTech (أَثر)

A next-generation FinTech app that turns spending habits into a living 3D Palm Tree Oasis — healthy finances make it flourish, reckless spending makes it wither.

## Stack

| Layer | Technology |
|-------|-----------|
| Backend | FastAPI (Python 3.12), Uvicorn |
| Frontend | Flutter Web |
| Database | Supabase (PostgreSQL) |
| Auth | Supabase Auth + PyJWT |
| 3D Engine | Spline (Flutter integration) |

## Project Structure

```
.
├── backend/              # FastAPI backend
│   ├── app/
│   │   ├── main.py       # App entrypoint, CORS middleware
│   │   ├── core/
│   │   │   └── config.py # Settings via pydantic-settings (.env)
│   │   ├── business/     # Business logic / facades
│   │   ├── persistence/  # Supabase data access
│   │   └── presentation/ # Routers (transactions, goals, analytics, oasis)
│   └── requirements.txt
├── athar_frontend/       # Flutter web app
│   └── lib/
│       └── config/
│           └── env.dart  # API_BASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY
├── start.sh              # Starts both services concurrently
└── replit.md             # This file
```

## How to Run

Click **Run** — `start.sh` launches both services:

| Service | Port | Preview |
|---------|------|---------|
| Flutter web | **5000** | Main preview pane |
| FastAPI | **8000** | Switch port in preview pane → Swagger UI at `/docs` |

The backend URL is automatically derived from `$REPLIT_DEV_DOMAIN` and passed to the Flutter build via `--dart-define=API_BASE_URL=...`.

## Environment Variables / Secrets

Set these in **Replit Secrets** (not in `.env`):

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Supabase service role key (backend only) |
| `SUPABASE_JWT_SECRET` | Supabase JWT secret (for token verification) |
| `SUPABASE_ANON_KEY` | Supabase anon/public key (Flutter client) |

`CORS_ORIGINS` is set automatically by `start.sh` to include the Replit dev domain.

## CORS Note

FastAPI crashes if `allow_credentials=True` is used with `allow_origins=["*"]`. The config default is now explicit origins (`localhost:5000`, `localhost:3000`). `start.sh` sets `CORS_ORIGINS` to the live Replit domain at startup. See `backend/app/main.py` for the guard that prevents a wildcard crash.

## User Preferences

- Keep existing project structure (Flutter in `athar_frontend/`, FastAPI in `backend/`)
- Do not migrate the database away from Supabase
