# Athar (أَثر) — Core Algorithms & Technical Architecture

> **Audience:** Technical jury & senior reviewers  
> **Version:** 1.0 · July 2026  
> **Stack:** FastAPI · PostgreSQL (Supabase) · Flutter Web · Spline 3D

This document formally describes the five core intelligence systems that power Athar's financial engine. Each section covers the mathematical model, the business rationale, and the exact implementation decisions made during development.

---

## Table of Contents

1. [Dynamic Recommended Savings (DRS) Algorithm](#1-dynamic-recommended-savings-drs-algorithm)
2. [Z-Score Anomaly Detection — Financial Radar](#2-z-score-anomaly-detection--financial-radar)
3. [Gamification & 3D Engine — The Oasis (الواحة)](#3-gamification--3d-engine--the-oasis-الواحة)
4. [Transaction Categorization Engine](#4-transaction-categorization-engine)
5. [Two-Ledger Architecture & Goal Lifecycle](#5-two-ledger-architecture--goal-lifecycle)

---

## 1. Dynamic Recommended Savings (DRS) Algorithm

### 1.1 Concept

A naive savings recommendation ("save 20% of income") ignores a user's real obligations and spending volatility. The DRS algorithm draws on the **Value-at-Risk (VaR)** concept from quantitative finance: instead of recommending a fixed percentage, it computes the *historical safe surplus* — the maximum amount a user can ring-fence into savings without risking their ability to cover daily expenses.

The question it answers is:

> *"Given this user's income, fixed obligations, and the unpredictable nature of their discretionary spending, what is the largest amount they can safely move to their Savings Wallet today?"*

### 1.2 Variables

| Symbol | Name | Definition |
|--------|------|------------|
| **AMI** | Avg. Monthly Income | Total confirmed income over the trailing 30-day window |
| **AFO** | Avg. Fixed Obligations | Sum of BNPL / instalment transactions (Tabby, Tamara, Spotii, Postpay) — recurring and predictable |
| **ADS** | Avg. Discretionary Spend | Total non-fixed expenses: groceries, entertainment, transport, etc. |
| **σ** | Discretionary Volatility | Standard deviation of *daily* expense totals over the trailing 30 days |
| **B** | Safety Buffer | A 10% liquidity reserve applied to AMI |

### 1.3 Formula

```
Net Discretionary Income (NDI) = AMI − AFO − ADS

Safety Buffer (B)              = AMI × 0.10

Dynamic Recommended Savings    = max(0, NDI − B − σ)
```

Breaking it down:

1. **`AMI − AFO`** removes all predictable, recurring obligations from gross income.
2. **`− ADS`** accounts for what the user *typically* spends on day-to-day needs.
3. **`− B`** (10% of income) protects a liquidity cushion — the user must never feel financially exposed after the transfer.
4. **`− σ`** (standard deviation of daily spend) is the VaR-inspired term. If the user's spending is highly erratic (σ is large), the system recommends *less*, because a volatile spender needs a larger real-world buffer. If spend is stable and predictable (σ → 0), more can safely flow to savings.

The result is floored at zero — the algorithm never suggests a negative savings amount.

### 1.4 Implementation Reference

**File:** `backend/app/business/facades/analytics_facade.py`

```python
safety_buffer     = total_income * 0.10
volatility        = statistics.stdev(daily_expense_totals)   # trailing 30-day window
net_discretionary = total_income - total_expenses - safety_buffer - volatility
drs               = round(max(0.0, net_discretionary), 1)
```

**BNPL detection keywords (AFO extraction):**
`"tabby"`, `"tamara"`, `"spotii"`, `"postpay"`

---

## 2. Z-Score Anomaly Detection — Financial Radar

### 2.1 Concept

Standard budgeting apps show totals. Athar's Financial Radar goes further: it detects *statistically unusual* spending events in real time, per category, and surfaces them as anomaly warnings. The mechanism is a **leave-one-out Z-Score analysis** applied across a user's transaction history.

### 2.2 Statistical Model

For each recent transaction *x* in category *c*, the system builds a historical reference pool *H* consisting of all *other* past transactions in the same category (excluding *x* itself — the "leave-one-out" principle, which prevents the current outlier from contaminating the mean it's being judged against).

```
μ_c  = mean(H_c)           # historical category mean
σ_c  = stdev(H_c)          # historical category std deviation

Z(x) = (x − μ_c) / σ_c
```

A transaction is flagged as anomalous when:

```
Z(x) > Z_threshold    where Z_threshold = 2.0
```

A Z-score above **2.0** places the transaction in the top ~2.3% of historical spend for that category — a statistically significant deviation that warrants user attention.

### 2.3 Guard Conditions

| Condition | Reason |
|-----------|--------|
| Minimum 2 historical samples required (`_MIN_HISTORICAL_SAMPLES = 2`) | The Z-score is undefined with fewer data points; the engine withholds the alert rather than producing a spurious one |
| Family transfer transactions excluded (`"family transfer"`, `"monthly family"`, `"تحويل عائلي"`) | Regular large intra-family transfers would permanently skew category means, generating false positives on routine transfers |

### 2.4 Output & Integration

Flagged anomalies flow into the `DashboardSummaryDTO` as warnings and are surfaced in the Flutter UI. They also feed directly into the Oasis health model (see Section 3.2).

**File:** `backend/app/business/analytics/insights_engine.py`

```python
_ANOMALY_Z_THRESHOLD    = 2.0
_MIN_HISTORICAL_SAMPLES = 2

z_score = (transaction_amount - historical_mean) / historical_stdev
if z_score > _ANOMALY_Z_THRESHOLD:
    flag_anomaly(transaction, category, z_score)
```

---

## 3. Gamification & 3D Engine — The Oasis (الواحة)

### 3.1 Design Philosophy

Financial data shown as raw numbers creates anxiety or indifference. The Oasis maps the user's financial health onto a living 3D palm grove: a thriving oasis means the user is saving consistently and spending responsibly; a drought-stricken desert reflects financial distress. No SAR amounts are shown — only the *feeling* of financial health.

The backend computes two scalar values — **growth level** and **health score** — which the Flutter layer communicates to the Spline 3D runtime via a JavaScript bridge.

### 3.2 Growth Algorithm — Palm Tree Visibility

Progress toward the active savings goal (`active_goal_progress_pct`, range 0.0 – 1.0) is converted to a `growth_level` on a 0–100 scale and then mapped to a discrete palm count:

```
growth_level  = active_goal_progress_pct × 100        (0 – 100)

palm_count    = 1 + floor(growth_level / 12.5)        (1 – 9 palms)
palm_count    = clamp(palm_count, 1, 9)
```

| Progress Range | growth_level | Palms Shown |
|----------------|-------------|-------------|
| 0% – 12.4% | 0 – 12.4 | 1 |
| 12.5% – 24.9% | 12.5 – 24.9 | 2 |
| 25.0% – 37.4% | 25 – 37.4 | 3 |
| 37.5% – 49.9% | 37.5 – 49.9 | 4 |
| 50.0% – 62.4% | 50 – 62.4 | 5 |
| 62.5% – 74.9% | 62.5 – 74.9 | 6 |
| 75.0% – 87.4% | 75 – 87.4 | 7 |
| 87.5% – 99.9% | 87.5 – 99.9 | 8 |
| 100% | 100 | 9 |

The 12.5-point step size is a deliberate choice: 9 palms over a 100-point scale gives roughly one new palm per 11% of goal completion, creating frequent, satisfying visual milestones.

### 3.3 Vitality Algorithm — Health Score & Drought Simulation

The `health_score` (0–100) starts at a nominal value and is modified by spending behaviour:

```
health_score += +2.0    for every SAVINGS category transaction
health_score −= 5.0    for every flagged ENTERTAINMENT anomaly
health_score  = clamp(health_score, 0, 100)
```

The score is then bucketed into three **weather conditions**:

| health_score | Weather State | Visual Effect |
|-------------|---------------|---------------|
| > 70 | ☀️ Sunny | Full colour, lush |
| 41 – 70 | ☁️ Cloudy | Slightly desaturated |
| ≤ 40 | ⛈️ Stormy | High sepia + desaturation — drought |

### 3.4 JS Bridge Integration

The Flutter widget `PalmOasisController` (في `palm_oasis_viewer.dart`) communicates with the vendored Spline runtime via `WebViewController.runJavaScript()`:

```dart
// Send palm count to Spline scene
await _controller.runJavaScript(
  'window.setVisiblePalmCount($clampedPalmCount);'
);

// Send health score — Spline applies CSS filter chain
await _controller.runJavaScript(
  'window.setHealth($healthScore);'
);
```

Inside the Spline runtime's JavaScript layer, `setHealth()` applies a `filter` CSS chain:

```
health ≥ 80  →  saturate(1.0)  sepia(0.0)   — vibrant, full life
health 50–79 →  saturate(0.6)  sepia(0.2)   — slight fatigue
health < 50  →  saturate(0.1)  sepia(0.7)   — near-drought
```

This produces a seamless visual metaphor: an overspending user watches their oasis literally wither without ever seeing a single SAR figure.

**Files:** `backend/app/business/gamification/engine.py` · `athar_frontend/lib/widgets/palm_oasis_viewer.dart`

---

## 4. Transaction Categorization Engine

### 4.1 Purpose

Raw bank transaction descriptions (e.g., `"POS TAMIMI MARKETS 04231"`, `"NOON.COM PURCHASE"`) are meaningless to a financial analytics layer. The Categorization Engine normalises every incoming transaction into one of 10 standard FinTech categories, enabling accurate spending breakdowns, pie chart distribution in the dashboard (لوحة التحكم), and reliable Z-score calculations per category.

### 4.2 Standard Category Taxonomy

| Category | Arabic Label | Examples |
|----------|-------------|---------|
| `FOOD` | طعام | Restaurants, cafes, delivery |
| `GROCERIES` | بقالة | Tamimi, Danube, Panda, Carrefour |
| `UTILITIES` | مرافق | Electricity (SEC), water, STC, Mobily |
| `ENTERTAINMENT` | ترفيه | Gaming, cinema, streaming |
| `HEALTH` | صحة | Pharmacies, clinics, hospitals |
| `TRANSPORT` | مواصلات | Uber, Careem, fuel stations |
| `HOUSING` | سكن | Rent, Airbnb, real estate |
| `SHOPPING` | تسوق | Noon, Amazon, Zara, H&M |
| `SAVINGS` | ادخار | Goal contributions, investment transfers |
| `UNCATEGORIZED` | غير مصنف | Fallback for unrecognised merchants |

### 4.3 Matching Algorithm

**File:** `backend/app/business/categorization/engine.py`

The engine uses a deterministic keyword-matching strategy with two pre-processing steps to maximise accuracy:

**Step 1 — Arabic normalisation**
The Arabic definite article "ال" is stripped from transaction descriptions before matching, so `"التميمي"` and `"تميمي"` both resolve to `GROCERIES`.

**Step 2 — Longest-match-first ordering**
The keyword dictionary is sorted by keyword length in *descending* order before any comparison. This prevents substring collisions: the keyword `"postpay"` must not be swallowed by a shorter `"pay"` entry mapping to a different category.

```python
sorted_keywords = sorted(keyword_map.items(),
                         key=lambda kv: len(kv[0]),
                         reverse=True)   # longest first

for keyword, category in sorted_keywords:
    if keyword in normalised_description:
        return category

return CategoryEnum.UNCATEGORIZED   # explicit fallback — never silent
```

**Step 3 — Single source of truth**
`CategoryEnum` is defined once in `backend/app/business/categorization/models.py` and imported by every layer that references categories — the categorisation engine, the analytics facade, the repository queries, and the API schemas. There is no string-literal duplication of category names anywhere in the codebase.

---

## 5. Two-Ledger Architecture & Goal Lifecycle

### 5.1 The Two-Ledger Model

Athar enforces a strict financial separation between two conceptually distinct pools of money:

| Ledger | Arabic Name | Role |
|--------|-------------|------|
| **Current Account** | الحساب الجاري | Liquid cash — used for daily spending |
| **Savings Wallet** | محفظة الادخار | Ring-fenced funds — tied to a savings goal |

Neither balance is stored as a literal column. Both are *computed on demand* from the immutable transaction ledger, ensuring auditability and eliminating synchronisation bugs.

### 5.2 Balance Formulas

```
Current Account Balance  = BASELINE_CURRENT + Σ(income) − Σ(expenses)
                         = 8,500 + total_income − total_expenses

Savings Wallet Balance   = BASELINE_SAVINGS + active_goal.saved_amount
                         = 15,000 + saved_amount
```

**Why baselines?**
The baselines (`8,500` and `15,000` SAR) represent a realistic starting financial snapshot for the demo user. They allow the app to open with meaningful, non-zero balances that reflect a plausible Saudi household financial profile, without requiring a pre-seeded transaction history.

### 5.3 Goal Progress Computation

```
progress_ratio = min(1.0, savings_wallet_balance / target_amount)
```

This ratio (0.0 – 1.0) feeds directly into the Oasis growth algorithm (Section 3.2) and drives the goal progress bar in the Dashboard (لوحة التحكم).

### 5.4 Goal Lifecycle State Machine

A savings goal moves through a strict set of states:

```
                  ┌─────────────────────────────────┐
                  │                                 │
              [ACTIVE]                              │
             /        \                             │
    (wallet ≥ target)  (user cancels)               │
           /                \                       │
    [COMPLETED]          [CANCELLED]            [ARCHIVED]
    (moved to history,   (refund issued,        (legacy alias
     Oasis celebrates)   Oasis resets)           = COMPLETED)
```

| State | Trigger | Financial Effect | Oasis Effect |
|-------|---------|-----------------|--------------|
| `ACTIVE` | Goal created | `saved_amount` accumulates | Palms grow with progress |
| `COMPLETED` | Wallet balance ≥ target | Goal locked in history | Full 9-palm celebration |
| `CANCELLED` | User cancels | **Refund issued** (see 5.5) | Oasis resets to baseline |
| `ARCHIVED` | Legacy alias | Same as COMPLETED | Same as COMPLETED |

### 5.5 Cancellation Refund — Atomic Transaction Logic

When a user cancels an active goal (إلغاء الهدف), the system must instantly restore their liquidity. This is handled as a single atomic operation:

1. The goal's `status` is updated to `CANCELLED` via a direct table UPDATE (bypassing the RPC layer, which only handles `ACTIVE → COMPLETED` transitions).
2. A new `INCOME` transaction is created in the *same database call*, with:
   - `amount = cancelled_goal.saved_amount`
   - `description = "REFUND: <goal_name>"`
   - `category = UNCATEGORIZED`

Because the Current Account balance is computed as `BASELINE + Σ(income) − Σ(expenses)`, the refund transaction immediately increases the displayed balance by the exact `saved_amount` — no balance column needs updating. The ledger is self-healing by design.

**File:** `backend/app/business/facades/goal_facade.py`

```python
async def cancel_goal(self, user_id: str, goal_id: str) -> Goal:
    cancelled = await self.goal_repo.cancel_goal(user_id, goal_id)
    await self.transaction_repo.create_transaction(
        user_id    = user_id,
        amount     = cancelled.saved_amount,
        category   = CategoryEnum.UNCATEGORIZED,
        description= f"REFUND: {cancelled.name}",
        tx_type    = TransactionType.INCOME,
    )
    return cancelled
```

---

## Appendix — Architecture Invariants

The following constraints are enforced across the entire codebase and must not be violated:

| Invariant | Rule |
|-----------|------|
| **Single analytics source** | `GET /analytics/{user_id}` is the *only* source of financial truth. Both the Dashboard tab and the Oasis tab consume `DashboardSummaryDTO` from this endpoint — no secondary oasis-specific endpoint exists. |
| **Immutable ledger** | Balances are never stored as literals. All balance reads are computed from the transaction log. |
| **CategoryEnum ownership** | `backend/app/business/categorization/models.py` is the single definition of all 10 categories. No other file may define or duplicate category string literals. |
| **Single port** | FastAPI on port 5000 serves both the REST API and the compiled Flutter Web build. No separate frontend server exists in production. |
| **ES256 JWT** | Supabase issues asymmetric ES256 tokens. The `cryptography` Python package must be installed alongside `PyJWT`; without it, JWKS verification silently returns `None`. |

