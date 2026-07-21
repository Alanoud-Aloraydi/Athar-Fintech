# 🚀 Deploying Athar-Fintech (live, public, free)

This guide gets a **single public URL** where anyone can open the app and try
it with a ready-made demo account. One free [Render](https://render.com)
service hosts *everything* — the FastAPI backend **and** the Flutter web app
are served from the same origin, so there is no CORS setup and nothing else to
host.

```
Browser ──▶ https://athar-fintech.onrender.com
                 ├── /            Flutter web app
                 ├── /docs        Swagger API explorer
                 └── /analytics…  FastAPI endpoints
                          └──▶ Supabase (PostgreSQL + Auth)
```

---

## What you need first

Four values from your **Supabase** project (Project Settings → API):

| Value | Where |
|-------|-------|
| `SUPABASE_URL` | Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Settings → API → `anon` `public` key |
| `SUPABASE_SERVICE_KEY` | Settings → API → `service_role` key (keep secret!) |
| `SUPABASE_JWT_SECRET` | Settings → API → JWT Settings → JWT Secret |

> The `service_role` key is powerful (bypasses row-level security). Only ever
> paste it into Render's secret env vars or your local `.env` — never commit it.

---

## Step 1 — Deploy to Render

1. Make sure this repo is pushed to GitHub (it is).
2. Go to **[dashboard.render.com](https://dashboard.render.com)** → **New +** →
   **Blueprint**.
3. Connect the `Athar-Fintech` repository. Render detects
   [`render.yaml`](../render.yaml) automatically.
4. Render will prompt for the four secret values above (they are marked
   "sync: false", so they stay out of git). Paste them in.
5. Click **Apply**. The first build takes ~5–8 minutes (it compiles Flutter web
   inside the image). When it finishes you get a URL like
   `https://athar-fintech.onrender.com`.

> **Free-plan note:** the service sleeps after ~15 minutes of inactivity. The
> first visit after it sleeps takes ~50 seconds to wake up, then it's fast. For
> a portfolio link this is usually fine; upgrade to a paid instance if you want
> it always-on.

---

## Step 2 — Whitelist the URL in Supabase (for password reset)

Supabase → **Authentication → URL Configuration** → **Redirect URLs** → add your
Render URL (e.g. `https://athar-fintech.onrender.com`). This is only needed for
the "forgot password" email link; login/signup work without it.

---

## Step 3 — Plant the demo account + data

This creates one ready-to-try account and fills it with a realistic ~30-day
Saudi financial story that exercises every feature (see the scenario notes at
the bottom).

From your machine, in the repo root:

```bash
# 1. Point the seeder at your Supabase project (service key needed)
export SUPABASE_URL="https://xxxx.supabase.co"
export SUPABASE_SERVICE_KEY="your-service-role-key"

# 2. Install backend deps if you haven't (the seeder reuses the app's engines)
pip install -r backend/requirements.txt

# 3. Seed
python scripts/seed_demo.py
```

On Windows PowerShell, use `$env:SUPABASE_URL="…"` instead of `export`.

The script is **idempotent** — re-run it any time to reset the demo account to
a clean, identical state. It prints the login credentials when it finishes.

**Default demo login:**

| Email | Password |
|-------|----------|
| `demo@athar-fintech.app` | `AtharDemo2026` |

(Override with `DEMO_EMAIL` / `DEMO_PASSWORD` env vars before seeding.)

---

## Step 4 — Share it

Send people the Render URL. They log in with the demo credentials above and can
explore the dashboard, the transactions, the savings goal, and the 3D oasis
immediately — no signup required.

---

## Running locally instead (optional)

```bash
# Backend + web, one command (needs Flutter + Python installed)
export SUPABASE_URL=...  SUPABASE_ANON_KEY=...  SUPABASE_JWT_SECRET=...
bash start.sh
# → http://localhost:5000  (app)   http://localhost:5000/docs  (API)
```

---

## What the demo data is designed to show

The seeder (`scripts/seed_demo.py`) plants transactions for a young Saudi
professional so each algorithm has something real to react to:

| Feature | How the data triggers it |
|---------|--------------------------|
| **Offline categorization** | Transactions span all 10 categories (Saudi merchants: بندة، التميمي، كارفور، البيك، النهدي، STC، موبايلي، نمشي…). |
| **Two-ledger balances** | A 16,000 SAR salary + realistic expenses drive the current account and savings wallet. |
| **Goal + trajectory** | An ACTIVE "صندوق الطوارئ" goal ~88% funded and slightly **ahead** of the linear pace. |
| **Saving streak** | 12 consecutive days of daily saving → a live streak. |
| **Z-Score anomaly** | One unusually large `Amazon.sa - laptop` purchase "today" flags against the user's own shopping average. |
| **Family-transfer exclusion** | A large `تحويل عائلي` is deliberately **not** flagged — a KSA cultural norm, not an anomaly. |
| **Committed obligations** | `Tabby` / `Tamara` installments tracked as fixed obligations, excluded from safe-to-spend. |
| **Oasis health & palms** | High health (thriving) and a lush palm count driven by goal progress. |

Because every date is computed relative to *when you run the seeder*, the
anomaly, the streak, and the 30-day insights stay valid on any day.
