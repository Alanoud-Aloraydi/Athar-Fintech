<div align="center">

# 🌴 Athar (أَثر) — `Athar-Fintech`
### *Where Your Financial Habits Leave a Mark.*

**A bilingual (Arabic/English) FinTech application that turns spending habits into a living 3D Palm Tree Oasis — healthy finances make it flourish, reckless spending makes it wither.**

[![Python](https://img.shields.io/badge/Python-3.12+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-High%20Performance-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![Flutter](https://img.shields.io/badge/Flutter-Web-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com/)
[![Three.js](https://img.shields.io/badge/Three.js-3D%20Engine-000000?style=for-the-badge&logo=three.js&logoColor=white)](https://threejs.org/)
[![Status](https://img.shields.io/badge/Status-MVP%20Complete-brightgreen?style=for-the-badge)]()

</div>

---

## 🔗 Try it live

**▶️ Live app:** https://athar-fintech.onrender.com

Log in with the ready-made demo account — no signup needed:

| Email | Password |
|-------|----------|
| `demo@athar-fintech.app` | `AtharDemo2026` |

The demo account is pre-loaded with a realistic ~30-day Saudi financial story
(Saudi merchants, essential obligations, a savings goal, a saving streak, and a
flagged spending anomaly) so every feature is visible immediately.

> First load may take ~50s while the free host wakes up, then it's fast.
> Video walkthrough: https://drive.google.com/file/d/1TwwIKmniQ0JET9fD8qABkJQ2oGZ0aJ8t/view?usp=sharing
> Want to deploy your own copy? See **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)**.

---

## 🪷 Overview

**Athar** *(Arabic: أَثر — "trace" or "impact")* is built on a simple but powerful premise: **every financial decision leaves a trace.**

Instead of burying users in spreadsheets and jargon, Athar renders their financial life as a **3D Palm Tree Oasis (واحة)**. Disciplined saving and healthy spending habits cause the Oasis to flourish with up to 30 palms; reckless spending causes it to wither. It's financial literacy, gamified — without ever compromising on bank-grade engineering rigor or user privacy.

---

## ✨ Features

### 🔒 Privacy-First Offline Categorization
Athar **never sends transaction data to a third-party LLM or external AI API**. Instead:
- Transactions are classified by a **proprietary, locally-executed Regex & Dictionary Engine** covering 10 bilingual (Arabic/English) categories.
- Categorization logic runs entirely inside the Business Layer — fully deterministic, auditable, and zero data leakage.

### 🌴 Dynamic 3D Gamification Engine
- Real-time procedural 3D Oasis powered by **Three.js** (vendored locally, no CDN): 30 palms
  placed by a golden-angle (phyllotaxis) formula around a 3D pond on a 3D sand ground.
- Palm count (1–30) and scene health driven by the user's savings wallet balance and spending health score.
- Scene synced across Dashboard and Oasis tabs via the same `DashboardSummaryDTO` source of truth.

### 💰 Two-Ledger Financial Model
| Ledger | Formula |
|--------|---------|
| Current Account | `Baseline (8,500 SAR) + income − expenses` |
| Savings Wallet | `Baseline (15,000 SAR) + active goal saved amount` |

Goal progress is computed from the **live savings wallet balance**, not a raw DB field — so Dashboard, Oasis, and Goals screens are always consistent.

### 🎯 Savings Goal Lifecycle
Three clean terminal states — all via `PATCH /goals/{user_id}/{goal_id}/status`:

| Status | Trigger | Financial Effect |
|--------|---------|-----------------|
| `COMPLETED` | Wallet balance ≥ target | Goal archived to history, wallet stays |
| `CANCELLED` | User exits early | Saved amount refunded as INCOME to current account, Oasis resets |
| `ARCHIVED` | Legacy alias | Treated identically to COMPLETED |

### 📊 10-Category Spending Engine
`FOOD` · `GROCERIES` · `UTILITIES` · `ENTERTAINMENT` · `HEALTH` · `TRANSPORT` · `HOUSING` · `SHOPPING` · `SAVINGS` · `UNCATEGORIZED`

Fully bilingual rules (Arabic merchant names + English keywords) defined in a single source-of-truth file.

### ⚡ Enterprise-Grade Backend
Strict **3-Tier Layered Architecture** (Presentation → Business → Persistence) + a shared **Core** layer, unified via the **Facade Design Pattern**.

---

## 🛠️ Tech Stack

| Layer | Technology | Version | Role |
|-------|-----------|---------|------|
| **Backend Runtime** | Python | 3.12+ | FastAPI server runtime |
| **API Framework** | FastAPI | latest | REST API, auto-docs (Swagger UI) |
| **ASGI Server** | Uvicorn | latest | Production-grade async server |
| **Frontend** | Flutter Web | 3.19+ | Cross-platform UI framework |
| **Database** | Supabase (PostgreSQL) | — | Data persistence + Auth |
| **Auth** | Supabase Auth + PyJWT | — | ES256 JWT verification |
| **Cryptography** | `cryptography` (Python) | — | Required for ES256 asymmetric JWT support |
| **Rate Limiting** | SlowAPI | — | API endpoint protection |
| **Config** | pydantic-settings | — | Type-safe env variable loading |
| **3D Engine** | Three.js | r128 | Procedural 3D Oasis scene (vendored locally) |
| **Internationalization** | intl (Dart) | — | Arabic/English number & date formatting |
| **HTTP Client** | http (Dart) | — | Flutter → FastAPI API calls |

> **Note on 3D assets:** the oasis is a fully procedural Three.js scene — `oasis_viewer.html` plus a locally-vendored `three.min.js` inside `athar_frontend/assets/oasis/`. The app makes **zero CDN requests** at runtime for 3D content, and there is no external scene file or watermark.

---

## 🏗️ Architecture

| Layer | Responsibility |
|-------|----------------|
| **Presentation** | FastAPI routers, DTOs/schemas, input validation |
| **Business** | Facades, Categorization Engine, Gamification Rules Engine |
| **Persistence** | Repositories, Supabase (PostgreSQL) adapters |
| **Core** | Config, security/auth (ES256 JWT), logging, custom exceptions |

Routers **never** call repositories directly — they call a Facade method, which internally orchestrates categorization, gamification updates, and persistence.

---

## 📁 Project Structure

```
.
├── athar_frontend/                   # Flutter Web application
│   ├── lib/
│   │   ├── config/
│   │   │   └── env.dart              # API_BASE_URL, SUPABASE_URL/KEY (--dart-define)
│   │   ├── models/
│   │   │   └── models.dart           # All DTOs: DashboardSummary, Goal, Transaction, etc.
│   │   ├── services/
│   │   │   ├── api_service.dart      # All HTTP calls to the FastAPI backend
│   │   │   └── auth_service.dart     # Supabase auth wrapper
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── dashboard_screen.dart # Balance cards, savings wallet, goal CTA
│   │   │   ├── farm_screen.dart      # 3D Oasis tab (uses DashboardSummary for sync)
│   │   │   ├── transactions_screen.dart
│   │   │   ├── profile_screen.dart   # Goal history, account info
│   │   │   └── main_navigation_screen.dart
│   │   └── widgets/
│   │       ├── palm_oasis_viewer.dart     # PalmOasisController wrapper
│   │       ├── oasis_iframe_web.dart      # Web postMessage bridge to the 3D HTML
│   │       └── common_widgets.dart        # Shared UI components
│   ├── assets/
│   │   └── oasis/
│   │       ├── oasis_viewer.html          # Procedural Three.js oasis (postMessage API)
│   │       └── three.min.js               # Three.js r128 (vendored, no CDN)
│   └── test/
│       └── dashboard_screen_error_test.dart
│
├── backend/                          # FastAPI application
│   ├── app/
│   │   ├── main.py                   # App entrypoint, CORS middleware
│   │   ├── core/
│   │   │   ├── config.py             # pydantic-settings (reads Replit Secrets)
│   │   │   └── security.py           # ES256 JWT verification (PyJWT + cryptography)
│   │   ├── business/
│   │   │   ├── facades/
│   │   │   │   ├── analytics_facade.py   # Dashboard + DRS calculation
│   │   │   │   ├── goal_facade.py        # Goal CRUD + cancel_goal (refund logic)
│   │   │   │   ├── oasis_facade.py       # Health score + streak computation
│   │   │   │   └── transaction_facade.py
│   │   │   ├── categorization/
│   │   │   │   ├── models.py             # CategoryEnum (10 categories) — source of truth
│   │   │   │   └── engine.py             # Bilingual regex/dictionary engine
│   │   │   └── gamification/             # Oasis behavior-mapping rules
│   │   ├── persistence/
│   │   │   └── repositories/
│   │   │       ├── goal_repo.py          # Supabase queries for goals
│   │   │       └── transaction_repo.py
│   │   └── presentation/
│   │       ├── routers/
│   │       │   ├── analytics.py          # GET /analytics/dashboard/{user_id}
│   │       │   ├── goals.py              # CRUD + PATCH /goals/.../status
│   │       │   ├── oasis.py              # GET /oasis/state/{user_id}
│   │       │   └── transactions.py       # CRUD /transactions
│   │       ├── schemas/
│   │       │   ├── analytics.py          # DashboardSummaryDTO, GoalProgressDTO
│   │       │   ├── goals.py              # GoalDTO, GoalStatusUpdateDTO
│   │       │   ├── oasis.py              # OasisStateDTO
│   │       │   └── transactions.py
│   │       └── dependencies.py           # FastAPI DI wiring (repos → facades)
│   ├── supabase/
│   │   └── migrations/                   # 000–007 SQL migration files
│   └── requirements.txt
│
├── scripts/
│   └── seed_demo.py                  # Plants the ready-to-try demo account + data
├── docs/
│   └── DEPLOYMENT.md                 # Step-by-step guide to host it live (free)
├── Dockerfile                        # Multi-stage build: Flutter web + FastAPI in one image
├── render.yaml                       # One-click Render Blueprint (single public URL)
├── start.sh                          # Local/Replit entry: pip install → flutter build → uvicorn
└── replit.md                         # Developer notes & Replit-specific config
```

---

## 🚀 Deploying live (recommended)

The fastest way to a public, shareable link is a **free Render service** that
serves the API and the Flutter web app from one URL — full walkthrough in
**[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** (deploy + seed the demo account in
about 10 minutes). The [`Dockerfile`](Dockerfile) and [`render.yaml`](render.yaml)
make it a Blueprint deploy: connect the repo, paste your Supabase keys, done.

---

## 🚀 Running on Replit

Click **Run** — `start.sh` handles everything automatically:

1. Installs Python dependencies (`pip install -r requirements.txt`)
2. Fetches Flutter packages (`flutter pub get`)
3. Builds Flutter web with injected env vars (hash-cached — skips rebuild if source unchanged)
4. Starts FastAPI via Uvicorn on **port 5000** (serves both the API and the Flutter web build)

| URL | What you get |
|-----|-------------|
| `/` | Flutter web app (main preview) |
| `/docs` | Swagger UI (interactive API explorer) |

## 🔑 Required Secrets

Set these in **Replit Secrets** (not in `.env`):

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Service role key (backend — bypasses RLS) |
| `SUPABASE_JWT_SECRET` | ES256 public key for JWT verification |
| `SUPABASE_ANON_KEY` | Anon/public key (Flutter Supabase client) |
| `SESSION_SECRET` | Random secret for session signing |

---

## 🧪 Tests

```bash
# Flutter widget tests
cd athar_frontend && flutter test
```

Backend: FastAPI endpoints are covered by the Swagger UI and manual integration testing via Supabase.

---

## 👥 The Team

<div align="center">

| Member | Role | Focus Area |
|--------|------|------------|
| **Alanoud Aloraydi** | 🔧 Backend Engineer & Integration | FastAPI, Persistence, Categorization Engine |
| **Sarah** | 🎨 Frontend Engineer | Flutter UI/UX & Design |
| **Reema Alshahrani** | 🎮 Gamification | Flutter–Three.js Integration & 3D Oasis Logic |

</div>

---

<div align="center">

### 🌴 *Athar — Every transaction leaves a trace. Make yours count.*

</div>
