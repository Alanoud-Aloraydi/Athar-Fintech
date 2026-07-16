<div align="center">

# 🌴 Athar (أَثر) — `Athar-Fintech`
### *Where Your Financial Habits Leave a Mark.*

**A next-generation FinTech application designed around Open Banking principles and immersive 3D Gamification — transforming abstract spending data into a living, breathing digital Oasis.** *(MVP Note: account aggregation is simulated via Mock Data for this hackathon build — see the Open Banking scope note below.)*

[![Python](https://img.shields.io/badge/Python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-High%20Performance-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![Flutter](https://img.shields.io/badge/Flutter-Cross--Platform-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com/)
[![Spline](https://img.shields.io/badge/Spline-3D%20Engine-FF3366?style=for-the-badge&logo=spline&logoColor=white)](https://spline.design/)
[![License](https://img.shields.io/badge/License-Proprietary-red?style=for-the-badge)]()
[![Status](https://img.shields.io/badge/Status-In%20Development-yellow?style=for-the-badge)]()

</div>

---

## 🪷 Overview

**Athar** *(Arabic: أَثر — "trace" or "impact")* is built on a simple but powerful premise: **every financial decision leaves a trace.**

Instead of burying users in spreadsheets and jargon, Athar renders their financial life as a **3D Palm Tree Oasis**. Disciplined saving and healthy spending habits cause the Oasis to flourish; reckless spending and missed goals cause it to wither. It's financial literacy, gamified — without ever compromising on bank-grade engineering rigor or user privacy.

> 📎 For UML diagrams, sequence flows, and detailed design rationale, see **[`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)**.

---

## ✨ Features & Unique Selling Propositions

### 🔒 Privacy-First Offline Categorization
Athar **never sends transaction data to a third-party LLM or external AI API** for spending analysis. Instead:

- Transactions are classified using a **proprietary, locally-executed Regex & Dictionary Engine**.
- Categorization logic runs entirely inside our **Business Layer**, fully deterministic and auditable.
- Zero external data leakage — spending data never leaves our infrastructure boundary for classification purposes.

> **Why it matters:** Financial data is among the most sensitive data a user owns. Athar treats offline-first categorization as a *security feature*, not a limitation.

### 🌴 Dynamic 3D Gamification Engine
- Real-time **3D scenes powered by Spline**, embedded natively inside Flutter.
- A **behavior-to-visual mapping system** translating budget adherence, savings streaks, and spending anomalies into tangible changes in the Oasis.
- Fully interactive: users rotate, zoom, and explore their financial "farm" in 3D space.

### 🏦 Open Banking-Inspired Architecture *(MVP Scope Note)*
- The system's **data model and Persistence layer are designed around Open Banking aggregation principles**, anticipating a unified, real-time view of a user's finances across institutions.
- ⚠️ **Direct bank API integration is explicitly out-of-scope for this hackathon MVP** due to time constraints. Live account linking, OAuth-based consent flows, and real institution connectors are deferred to a post-MVP milestone.
- For this build, account aggregation is **simulated using structured Mock Data** (representative transaction sets injected directly into the Persistence layer), allowing the team to focus engineering effort entirely on the two features that matter most for the demo: the **offline Categorization Engine** and the **Gamification logic**.
- The architecture is intentionally structured so that swapping Mock Data for a real Open Banking connector later requires **no changes to the Business or Presentation layers** — only a new Persistence-layer adapter.

### ⚡ Enterprise-Grade Backend
- Strict **3-Tier Layered Architecture** (Presentation → Business → Persistence) plus a shared **Core** layer, unified via the **Facade Design Pattern**, ensuring maintainability and testability as the platform scales.

---

## 🏗️ Enterprise Architecture

Athar's backend is organized into four distinct layers with **one-directional dependency flow**:

| Layer | Responsibility |
|-------|-----------------|
| **Presentation** | FastAPI routers, request/response schemas (DTOs), input validation, API versioning. Talks *only* to Facades. |
| **Business** | Domain services, the Regex/Dictionary Categorization Engine, the Gamification Rules Engine, and the **Facade classes** that orchestrate cross-cutting operations. |
| **Persistence** | Repositories and Supabase (PostgreSQL) client adapters. Owns all query logic and data mapping. |
| **Core** | Cross-cutting concerns shared by every layer: configuration, security/auth utilities, logging, custom exceptions, and shared constants. |

The **Facade Design Pattern** sits at the boundary between Presentation and Business: each Business module exposes exactly one Facade class as its public entry point. Routers never call repositories or engines directly — they call a Facade method, which internally orchestrates categorization, gamification updates, and persistence as a single atomic unit of work.

Full UML (Package, Class, and Sequence diagrams) and the detailed design rationale live in **[`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)**.

---

## 📁 Folder Structure

```
Athar-Core/
│
├── 📱 frontend/                      # Flutter Application
│   ├── lib/
│   │   ├── screens/                  # UI Screens (Dashboard, Oasis View, etc.)
│   │   ├── widgets/                  # Reusable Flutter widgets
│   │   ├── services/                 # API clients, Spline bridge services
│   │   └── main.dart
│   ├── assets/                       # Spline scenes, fonts, icons
│   └── pubspec.yaml
│
├── 🐍 backend/                       # Python / FastAPI Application
│   └── app/
│       ├── presentation/             # 🎤 Routers, Schemas, API Controllers
│       ├── business/                 # 🧠 Domain Logic, Facades, Rules Engines
│       │   ├── facades/
│       │   ├── categorization/       # Regex/Dictionary Engine
│       │   └── gamification/         # Oasis behavior-mapping logic
│       ├── persistence/              # 🗄️ Repositories, Supabase Adapters
│       └── core/                     # ⚙️ Config, Security, Logging, Exceptions
│   ├── tests/
│   ├── requirements.txt
│   └── main.py
│
├── 📚 docs/                          # Architecture & design documentation
│   └── ARCHITECTURE.md               # UML diagrams + design rationale
│
├── .env.example
├── .gitignore
└── README.md
```

---

## 🚀 Local Setup

Athar is developed **entirely on local machines** — no cloud IDEs, no Codespaces. Each developer runs their own local backend and frontend environment against a shared Supabase project.

### ✅ Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.11+ | Backend runtime |
| Flutter SDK | 3.19+ | Frontend runtime |
| Supabase Account | — | Database & Auth |
| Git | Latest | Version control |

---

### 🐍 Backend Setup (FastAPI)

```bash
# 1. Clone the repository
git clone https://github.com/<org>/Athar-Core.git
cd Athar-Core/backend

# 2. Create and activate a local virtual environment
python -m venv venv
source venv/bin/activate      # On Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Configure environment variables
cp ../.env.example .env
# ➜ Fill in SUPABASE_URL, SUPABASE_KEY, and other secrets in .env

# 5. Run the local development server
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

> 📖 Interactive API docs available locally at: `http://127.0.0.1:8000/docs`

---

### 📱 Frontend Setup (Flutter)

```bash
# 1. Navigate to the frontend directory
cd Athar-Core/frontend

# 2. Fetch project dependencies
flutter pub get

# 3. Configure environment variables
cp ../.env.example .env
# ➜ Set BACKEND_API_URL to http://127.0.0.1:8000

# 4. Run the application on a connected device or emulator
flutter run
```

> 💡 **Spline Integration Tip:** Ensure Spline scene assets under `assets/spline/` are correctly referenced in `pubspec.yaml` before running the 3D Oasis screen.

---

## 🧪 Running Tests

```bash
# Backend unit & integration tests
cd backend
pytest -v --cov=app

# Frontend widget tests
cd frontend
flutter test
```

---

## 👥 The Team

<div align="center">

| Member | Role | Focus Area |
|--------|------|------------|
| **Alanoud Aloraydi** | 🔧 Backend Engineer | Backend & Data Engine — FastAPI, Persistence, Categorization Engine |
| **Sarah** | 🎨 Frontend Engineer | Flutter UI/UX & Figma Design Systems |
| **Reema Alshahrani** | 🎮 Integration & Gamification Engineer | Flutter–Spline Integration & 3D Oasis Behavior Logic |

</div>

---

<div align="center">

### 🌴 *Athar — Every transaction leaves a trace. Make yours count.*

</div>
