---
name: Transaction write bug & fix
description: create_transaction_atomic RPC fails with Postgres error 42804 due to missing TEXT→enum casts; repo now bypasses it with table-level ops.
---

## The rule
Do NOT call `create_transaction_atomic` via Supabase RPC until migration 005 is applied to the Supabase project via the Dashboard SQL editor (`backend/supabase/migrations/005_fix_create_transaction_atomic_cast.sql`).

## Why
Migration 002 changed the function signature from `category_type`/`transaction_type` enum parameters to `TEXT`, but the INSERT body was not updated to add `::category_type` / `::transaction_type` casts. Postgres error 42804: "column category is of type category_type but expression is of type text".

Table-level `supabase.table("transactions").insert(...)` auto-casts string→enum, so the repository now uses direct table operations instead of the RPC.

## How to apply
1. Open Supabase Dashboard → SQL Editor.
2. Paste and run `backend/supabase/migrations/005_fix_create_transaction_atomic_cast.sql`.
3. After applying, you can optionally revert `transaction_repo.py` to use the RPC again for full atomicity — the function body now casts `p_category::category_type` and `p_type::transaction_type`.

## get_category_spending_stats
Returns 3 columns: `avg_amount`, `stddev_amount`, `sample_size` (BIGINT). The Python repo's `get_category_spending_stats` must return a 3-tuple `(float, float, int)`.
