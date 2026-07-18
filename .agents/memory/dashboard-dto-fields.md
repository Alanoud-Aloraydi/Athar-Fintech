---
name: Dashboard DTO field names
description: DashboardSummaryDTO field naming conventions and safe_to_spend sign behaviour after wealth-model refactor.
---

## Rule
`DashboardSummaryDTO` (and Flutter `DashboardSummary`) uses these field names — do NOT revert to the old names:

| Old (removed) | New | JSON key |
|---|---|---|
| `current_balance` | `total_wallet_balance` | `total_wallet_balance` |
| `total_income` | `current_month_income` | `current_month_income` |
| `total_expenses` | `current_month_expenses` | `current_month_expenses` |

`total_wallet_balance = _BASELINE_WEALTH (55,000 SAR) + (current_month_income − current_month_expenses)`

`safe_to_spend_today` is intentionally **allowed to be negative** — the Flutter `_SafeToSpendCard` handles the negative case with a red overspending warning. Do not add a `max(0.0, ...)` clamp back to `_safe_to_spend()`.

**Why:** The old formula (`balance = income − expenses`) was mathematically wrong for FinTech — it ignored cumulative wealth. The baseline simulates historical Alinma savings. Negative safe-to-spend is valid UX signal (overspending before payday).

**How to apply:** Any future endpoint or Flutter screen reading the dashboard response must use the new field names. `AnalyticsSummaryDTO` (different endpoint) still uses the old `total_income`/`total_expenses` — do not confuse the two DTOs.
