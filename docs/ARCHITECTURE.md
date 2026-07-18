<div align="center">

# 🏛️ Athar-Fintech — Software Architecture

**Design Document · Layered Architecture + Facade Pattern**

</div>

---

## 📖 Table of Contents

1. [Architectural Philosophy](#1-architectural-philosophy)
2. [Package Diagram](#2-package-diagram)
3. [Class Diagram](#3-class-diagram)
4. [Financial Model & Goal Lifecycle](#4-financial-model--goal-lifecycle)
5. [Sequence Diagram — Transaction Ingestion Flow](#5-sequence-diagram--transaction-ingestion-flow)
6. [Sequence Diagram — Goal Cancellation Flow](#6-sequence-diagram--goal-cancellation-flow)
7. [Design Rationale — Why Layered + Facade](#7-design-rationale--why-layered--facade)
8. [Extensibility Guidelines](#8-extensibility-guidelines)

---

## 1. Architectural Philosophy

Athar's backend is built on two complementary architectural decisions:

| Decision | Purpose |
|----------|---------|
| **3-Tier Layered Architecture** (Presentation → Business → Persistence, plus a cross-cutting **Core**) | Enforces separation of concerns and a strict, one-directional dependency flow. No layer may skip another. |
| **Facade Design Pattern** | Provides a single, stable entry point into each Business module, hiding internal orchestration complexity (categorization → gamification → persistence) from the Presentation layer. |

The combination guarantees that **the API surface (Presentation) is decoupled from implementation details** in the Business and Persistence layers — meaning the categorization engine, the gamification rules, or even the underlying database provider (Supabase) can evolve independently without breaking route contracts.

**Dependency Rule:** A layer may only depend on the layer directly beneath it. `Core` is the exception — it has no dependencies and may be imported by any layer.

```
Presentation  ──depends on──▶  Business  ──depends on──▶  Persistence
      │                            │                            │
      └────────────────────────────┴────────────▶  Core  ◀──────┘
```

---

## 2. Package Diagram

The package diagram shows the four top-level packages inside `backend/app/`, their internal modules, and the **allowed** dependency directions between them.

```mermaid
graph TB
    subgraph Presentation["📤 presentation"]
        P1[routers/]
        P2[schemas / DTOs]
        P3[dependencies.py]
    end

    subgraph Business["🧠 business"]
        B1["facades/\n(analytics · goal · oasis · transaction)"]
        B2["categorization/\n(Regex & Dictionary Engine)"]
        B3["gamification/\n(Oasis Rules Engine)"]
    end

    subgraph Persistence["🗄️ persistence"]
        D1["repositories/\n(goal_repo · transaction_repo)"]
        D2["supabase_client.py"]
    end

    subgraph Core["⚙️ core"]
        C1["config.py"]
        C2["security.py\n(ES256 JWT · PyJWT + cryptography)"]
        C3["exceptions.py"]
        C4["logging.py"]
    end

    P1 -->|calls| B1
    P2 -.->|used by| P1
    B1 -->|orchestrates| B2
    B1 -->|orchestrates| B3
    B1 -->|calls| D1
    D1 -->|uses| D2

    Presentation -.->|imports| Core
    Business -.->|imports| Core
    Persistence -.->|imports| Core

    style Presentation fill:#1f2937,stroke:#60a5fa,color:#fff
    style Business fill:#1f2937,stroke:#34d399,color:#fff
    style Persistence fill:#1f2937,stroke:#f59e0b,color:#fff
    style Core fill:#1f2937,stroke:#f87171,color:#fff
```

**Key observations:**
- `presentation` never imports from `persistence` directly — every cross-layer call is mediated by a Facade.
- There are **four Facades**, each the sole public entry point of its Business module: `AnalyticsFacade`, `GoalFacade`, `OasisFacade`, `TransactionFacade`.
- `Core` has no outbound dependencies — it is the only package that any layer can import freely.

---

## 3. Class Diagram

The class diagram illustrates the core domain classes, focused on the **Facade Pattern** implementation and the actual entity fields in the current codebase.

```mermaid
classDiagram
    class TransactionRouter {
        +create_transaction(payload: TransactionCreateDTO) TransactionResponseDTO
        +get_transactions(user_id: UUID) list~TransactionResponseDTO~
    }

    class GoalsRouter {
        +get_active_goal(user_id: UUID) GoalDTO
        +create_goal(payload: GoalCreateDTO) GoalDTO
        +transition_goal_status(user_id, goal_id, payload: GoalStatusUpdateDTO)
    }

    class AnalyticsRouter {
        +get_dashboard_summary(user_id: UUID) DashboardSummaryDTO
    }

    class OasisRouter {
        +get_oasis_state(user_id: UUID) OasisStateDTO
    }

    class TransactionFacade {
        <<Facade>>
        +process_and_store(payload: TransactionCreateDTO) TransactionResponseDTO
    }

    class GoalFacade {
        <<Facade>>
        +get_active_goal(user_id: UUID) Goal
        +create_goal(user_id: UUID, payload) Goal
        +transition_status(user_id, goal_id, new_status: str) Goal
        +cancel_goal(user_id: UUID, goal_id: UUID) Goal
    }

    class AnalyticsFacade {
        <<Facade>>
        +get_dashboard_summary(user_id: UUID) DashboardSummaryDTO
    }

    class OasisFacade {
        <<Facade>>
        +get_oasis_state(user_id: UUID) OasisStateDTO
    }

    class CategorizationEngine {
        -rules_dictionary: dict
        -regex_patterns: list~Pattern~
        +classify(description: str, amount: Decimal) CategoryEnum
    }

    class TransactionRepository {
        <<Repository>>
        -supabase_client: SupabaseClient
        +create_transaction(payload) Transaction
        +get_by_user(user_id: UUID) list~Transaction~
    }

    class GoalRepository {
        <<Repository>>
        -supabase_client: SupabaseClient
        +get_active_goal(user_id: UUID) Goal
        +create_goal(user_id: UUID, payload) Goal
        +transition_goal_status(goal_id: UUID, new_status: str) Goal
        +cancel_goal(user_id: UUID, goal_id: UUID) Goal
    }

    class SupabaseClient {
        <<Adapter>>
        -url: str
        -service_key: str
        +table(name: str) QueryBuilder
    }

    class Transaction {
        <<Entity>>
        +id: UUID
        +user_id: UUID
        +description: str
        +amount: Decimal
        +transaction_type: str
        +category: CategoryEnum
        +created_at: datetime
    }

    class Goal {
        <<Entity>>
        +goal_id: UUID
        +user_id: UUID
        +title: str
        +target_amount: Decimal
        +saved_amount: Decimal
        +status: GoalStatusEnum
        +created_at: datetime
    }

    class GoalStatusEnum {
        <<Enumeration>>
        ACTIVE
        COMPLETED
        CANCELLED
        ARCHIVED
    }

    class CategoryEnum {
        <<Enumeration>>
        FOOD
        GROCERIES
        UTILITIES
        ENTERTAINMENT
        HEALTH
        TRANSPORT
        HOUSING
        SHOPPING
        SAVINGS
        UNCATEGORIZED
    }

    TransactionRouter ..> TransactionFacade : depends on
    GoalsRouter ..> GoalFacade : depends on
    AnalyticsRouter ..> AnalyticsFacade : depends on
    OasisRouter ..> OasisFacade : depends on

    TransactionFacade ..> CategorizationEngine : orchestrates
    TransactionFacade ..> TransactionRepository : orchestrates

    GoalFacade ..> GoalRepository : orchestrates
    GoalFacade ..> TransactionRepository : creates refund on cancel

    AnalyticsFacade ..> TransactionRepository : reads
    AnalyticsFacade ..> GoalRepository : reads
    OasisFacade ..> TransactionRepository : reads
    OasisFacade ..> GoalRepository : reads

    TransactionRepository --> SupabaseClient : uses
    GoalRepository --> SupabaseClient : uses

    TransactionRepository ..> Transaction : persists
    GoalRepository ..> Goal : persists

    CategorizationEngine ..> CategoryEnum : produces
    Transaction --> CategoryEnum : has
    Goal --> GoalStatusEnum : has
```

**Key observations:**
- `GoalFacade.cancel_goal()` is distinct from `transition_status()` — it atomically updates the goal's status to `CANCELLED` **and** inserts a refund `INCOME` transaction into the Current Account, restoring the user's spending balance.
- `AnalyticsFacade` computes the **Two-Ledger** balance model (see Section 4) — it never reads a stored "current balance" field; it derives it from baseline constants and transaction aggregates.
- `Goal` does **not** have a `category` or `deadline` field — goal adherence is measured purely through the savings wallet balance vs. the target amount.
- `CategoryEnum` has exactly **10 values** — the single source of truth in `backend/app/business/categorization/models.py`, mirrored to Flutter as `AppCategory` in `models.dart`.

---

## 4. Financial Model & Goal Lifecycle

### 4.1 Two-Ledger Balance Model

Athar never stores a user's current balance as a literal database field. Instead, two virtual ledgers are computed on every dashboard request:

| Ledger | Formula | Baseline (SAR) |
|--------|---------|----------------|
| **Current Account** | `Baseline + Σ INCOME transactions − Σ EXPENSE transactions` | 8,500 |
| **Savings Wallet** | `Baseline + active_goal.saved_amount` | 15,000 |

**Why this matters architecturally:**
- Balance is always derived from raw transaction data — no risk of ledger drift between the balance field and the actual transaction history.
- The `AnalyticsFacade` is the **single source of truth** for both ledgers. The Dashboard screen and the Oasis (farm) tab both consume `DashboardSummaryDTO` from the same endpoint — guaranteeing that wallet balance, palm count, and health filter are always in sync across tabs.

### 4.2 Oasis Health Score & Daily Rate of Savings (DRS)

```
DRS = monthly_income − monthly_expenses − fixed_obligations − (10% safety_buffer)

oasis_health_score = clamp(0, 100, DRS / income × 100)
```

Palm count (1–9) and the CSS health filter applied to the Spline scene are derived **exclusively** from `DashboardSummaryDTO.oasisHealthScore` and the wallet-to-target ratio — never from a separate Oasis-specific API call.

### 4.3 Goal Lifecycle

All goal state transitions go through `PATCH /goals/{user_id}/{goal_id}/status`.

```mermaid
stateDiagram-v2
    [*] --> ACTIVE : POST /goals (create)
    ACTIVE --> COMPLETED : wallet_balance ≥ target\n(user confirms)
    ACTIVE --> CANCELLED : user exits early\n(refund INCOME auto-created)
    ACTIVE --> ARCHIVED : legacy alias → treated as COMPLETED
    COMPLETED --> [*]
    CANCELLED --> [*]
    ARCHIVED --> [*]
```

| Status | Trigger | Financial Side-Effect |
|--------|---------|----------------------|
| `COMPLETED` | `savings_wallet_balance >= target_amount` | Goal moves to history; wallet balance stays |
| `CANCELLED` | User requests cancellation | `saved_amount` refunded as an INCOME transaction to Current Account; Oasis resets to single palm |
| `ARCHIVED` | Legacy path | Identical to COMPLETED — no financial effect |

**Implementation note:** `CANCELLED` transitions bypass the Supabase RPC (which only handles ACTIVE→COMPLETED) and use a direct table-level `UPDATE` in `GoalRepository.cancel_goal()`, followed by an atomic `TransactionRepository.create_transaction()` to record the refund.

---

## 5. Sequence Diagram — Transaction Ingestion Flow

This diagram traces a single incoming transaction from the API boundary through categorization and persistence — the canonical example of the Facade orchestrating a multi-step Business operation.

```mermaid
sequenceDiagram
    autonumber
    actor Client as 📱 Flutter Client
    participant Router as 🎤 TransactionRouter
    participant Facade as 🧩 TransactionFacade
    participant CatEngine as 🔍 CategorizationEngine
    participant Repo as 🗄️ TransactionRepository
    participant DB as ☁️ Supabase (PostgreSQL)

    Client->>Router: POST /transactions (payload)
    activate Router
    Router->>Facade: process_and_store(payload)
    activate Facade

    Facade->>CatEngine: classify(description, amount)
    activate CatEngine
    Note over CatEngine: Bilingual regex + dictionary rules.<br/>No external API — fully offline.
    CatEngine-->>Facade: CategoryEnum
    deactivate CatEngine

    Facade->>Repo: create_transaction(payload, category)
    activate Repo
    Repo->>DB: INSERT into transactions
    activate DB
    DB-->>Repo: persisted row
    deactivate DB
    Repo-->>Facade: Transaction
    deactivate Repo

    Facade-->>Router: TransactionResponseDTO
    deactivate Facade
    Router-->>Client: 201 Created (JSON)
    deactivate Router
```

**Key observations:**
- The Router never talks to the Repository or the Categorization Engine directly — every call is mediated by the Facade.
- Categorization is fully offline — no external API call occurs, in line with the Privacy-First design principle.

---

## 6. Sequence Diagram — Goal Cancellation Flow

Goal cancellation is the most complex business operation: it must atomically transition the goal status **and** create a refund transaction so the user's current account balance is immediately restored.

```mermaid
sequenceDiagram
    autonumber
    actor Client as 📱 Flutter Client
    participant Router as 🎤 GoalsRouter
    participant Facade as 🧩 GoalFacade
    participant GoalRepo as 🎯 GoalRepository
    participant TxRepo as 🗄️ TransactionRepository
    participant DB as ☁️ Supabase (PostgreSQL)

    Client->>Router: PATCH /goals/{user_id}/{goal_id}/status\n{new_status: "CANCELLED"}
    activate Router
    Router->>Facade: cancel_goal(user_id, goal_id)
    activate Facade

    Facade->>GoalRepo: get_active_goal(user_id)
    activate GoalRepo
    GoalRepo-->>Facade: Goal (saved_amount, target_amount)
    deactivate GoalRepo

    Facade->>GoalRepo: cancel_goal(user_id, goal_id)
    activate GoalRepo
    Note over GoalRepo: Direct table UPDATE (bypasses RPC<br/>which only handles ACTIVE→COMPLETED)
    GoalRepo->>DB: UPDATE goals SET status='CANCELLED'
    activate DB
    DB-->>GoalRepo: updated row
    deactivate DB
    GoalRepo-->>Facade: Goal (status=CANCELLED)
    deactivate GoalRepo

    Facade->>TxRepo: create_transaction(refund_payload)
    activate TxRepo
    Note over TxRepo: type=INCOME, category=SAVINGS,<br/>amount=saved_amount (refund)
    TxRepo->>DB: INSERT into transactions
    activate DB
    DB-->>TxRepo: persisted row
    deactivate DB
    TxRepo-->>Facade: Transaction (refund)
    deactivate TxRepo

    Facade-->>Router: Goal (CANCELLED)
    deactivate Facade
    Router-->>Client: 200 OK
    deactivate Router
```

**Key observations:**
- The refund INCOME transaction is created **in the same Facade call** as the goal cancellation — if either step fails, the error surfaces immediately and neither side-effect is silently applied.
- After cancellation, `AnalyticsFacade.get_dashboard_summary()` will naturally reflect the refunded amount in the Current Account balance (through the Two-Ledger formula), and the Oasis resets to a single palm because `active_goal_target = 0`.

---

## 7. Design Rationale — Why Layered + Facade

### 7.1 Testability
Each layer can be unit-tested in isolation. Any Facade can be tested with mocked Repository and Engine collaborators — no database or HTTP server required.

### 7.2 Single Source of Truth for Financial Data
`AnalyticsFacade.get_dashboard_summary()` is the **only** code path that computes balances. Both the Dashboard screen and the Oasis tab fetch from this endpoint — there is no separate "oasis balance" endpoint that could drift out of sync. This is enforced by the architecture: the Oasis tab's `farm_screen.dart` calls `getDashboardSummary()`, not a separate oasis-specific calculation.

### 7.3 Replaceability
Because `Presentation` only knows about Facade method signatures, the entire Business or Persistence layer can be re-implemented (e.g., swapping Supabase for another PostgreSQL provider) with **zero changes to the Presentation layer or API contract**.

### 7.4 Privacy-First Categorization
The `CategorizationEngine` is a pure in-process function — no network call, no external AI API. Financial transaction data never leaves the infrastructure boundary for classification purposes. This is enforced structurally: the engine has no HTTP client and no outbound dependencies.

### 7.5 Reduced Cognitive Load for Small Teams
Developers working in Presentation never need to understand categorization rules or gamification logic — they only need Facade method signatures. This is critical for a team of 3 engineers working across distinct focus areas concurrently.

### 7.6 Alignment with Team Structure (Conway's Law)

| Layer / Concern | Primary Owner |
|------------------|----------------|
| Business (Categorization Engine), Persistence, Core | **Alanoud Aloraydi** |
| Flutter–Spline Integration, Oasis behavior mapping | **Reema Alshahrani** |
| Flutter UI/UX | **Sarah** |

---

## 8. Extensibility Guidelines

When adding a new capability to Athar, follow this checklist:

1. **Define the Entity/DTO** in `business/` or `presentation/schemas/` as appropriate.
2. **Implement domain logic** in a dedicated `business/<feature>/` module — never inline it in a router.
3. **Expose exactly one Facade method** for the new capability; do not let routers call more than one Business collaborator directly.
4. **Add a Repository method** in `persistence/repositories/` if new data access is required — never call `SupabaseClient` from outside `persistence/`.
5. **Write unit tests** for the Facade with mocked collaborators, and Flutter widget tests for any new screen.
6. **Update this document** — every new cross-layer flow of significance should be reflected in the Sequence Diagram section.
