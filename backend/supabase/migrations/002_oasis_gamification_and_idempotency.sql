-- =============================================================================
-- Migration 002: Oasis State Persistence, Idempotent Transactions, Smart Stats
-- =============================================================================
-- This migration assumes the base schema from the initial migration already
-- exists (profiles, goals, transactions, create_transaction_atomic,
-- goal_lifecycle_functions). It REPLACES `create_transaction_atomic` with a
-- superset signature (idempotency + Oasis deltas) — verify the balance-sign
-- logic below (`v_signed_amount`) matches your original function exactly
-- before applying to production; it was reconstructed to match the documented
-- behavior in `transaction_repo.py` (EXPENSE decreases, INCOME increases,
-- balance allowed to go negative).
--
-- Safe to run more than once: every DDL statement is guarded with
-- IF NOT EXISTS / CREATE OR REPLACE.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Idempotency for transactions
-- -----------------------------------------------------------------------------
-- Nullable so existing rows and clients that don't yet send a key are
-- unaffected. Uniqueness is scoped to (user_id, idempotency_key) rather than
-- globally — a client-generated UUID collision across two different users'
-- retries should never be possible anyway, but scoping it this way also lets
-- two completely unrelated users theoretically reuse a key without conflict,
-- which is irrelevant to correctness but keeps the constraint meaningful.
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_transactions_user_idempotency_key
    ON transactions (user_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. Oasis state — the persisted, cumulative counterpart to OasisImpact
-- -----------------------------------------------------------------------------
-- One row per user. `growth_level` and `health_score` are the running totals
-- that used to be recomputed from scratch by replaying every transaction on
-- every analytics call — this table makes that replay unnecessary.
-- `current_streak_days` / `longest_streak_days` / `last_positive_action_date`
-- track consecutive-day good-habit streaks (a SAVINGS transaction, i.e. any
-- transaction with a positive growth_delta, counts as "a positive action
-- today"). Environmental descriptors like `weather_condition` or
-- `visual_aura` are DERIVED from these numbers at read time in the Business
-- layer (see `GamificationEngine.derive_environment`) rather than stored here
-- — that keeps the "feel" of the Oasis tunable without a migration, while the
-- expensive-to-recompute part (the running totals) stays atomic and persisted.
CREATE TABLE IF NOT EXISTS oasis_states (
    user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    growth_level NUMERIC NOT NULL DEFAULT 0,
    health_score NUMERIC NOT NULL DEFAULT 100 CHECK (health_score BETWEEN 0 AND 100),
    current_streak_days INT NOT NULL DEFAULT 0,
    longest_streak_days INT NOT NULL DEFAULT 0,
    last_positive_action_date DATE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 3. create_transaction_atomic — now idempotent, now updates Oasis state too
-- -----------------------------------------------------------------------------
-- Single atomic statement per concern:
--   a) idempotent replay short-circuit (no balance/Oasis mutation on replay)
--   b) insert the transaction row
--   c) update profiles.current_balance
--   d) upsert oasis_states (growth/health running totals + streak logic)
-- All three writes (b, c, d) commit together or not at all, in the same way
-- the original function guaranteed for (b, c) alone.
CREATE OR REPLACE FUNCTION create_transaction_atomic(
    p_user_id UUID,
    p_amount NUMERIC,
    p_description TEXT,
    p_category TEXT,
    p_type TEXT,
    p_idempotency_key TEXT DEFAULT NULL,
    p_growth_delta NUMERIC DEFAULT 0,
    p_health_delta NUMERIC DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    amount NUMERIC,
    description TEXT,
    category TEXT,
    type TEXT,
    created_at TIMESTAMPTZ,
    idempotency_key TEXT,
    is_replay BOOLEAN,
    oasis_growth_level NUMERIC,
    oasis_health_score NUMERIC,
    oasis_streak_days INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing transactions%ROWTYPE;
    v_txn transactions%ROWTYPE;
    v_signed_amount NUMERIC;
    v_oasis_growth NUMERIC;
    v_oasis_health NUMERIC;
    v_oasis_streak INT;
    v_is_positive_action BOOLEAN;
BEGIN
    -- (a) Idempotent replay: a transaction with this (user_id,
    -- idempotency_key) pair already exists. Return it verbatim, plus the
    -- CURRENT Oasis snapshot, and do not touch the balance or Oasis state
    -- again — this is what makes a client-side network retry safe.
    IF p_idempotency_key IS NOT NULL THEN
        SELECT * INTO v_existing
        FROM transactions t
        WHERE t.user_id = p_user_id
          AND t.idempotency_key = p_idempotency_key
        LIMIT 1;

        IF FOUND THEN
            SELECT o.growth_level, o.health_score, o.current_streak_days
            INTO v_oasis_growth, v_oasis_health, v_oasis_streak
            FROM oasis_states o
            WHERE o.user_id = p_user_id;

            RETURN QUERY SELECT
                v_existing.id, v_existing.user_id, v_existing.amount,
                v_existing.description, v_existing.category, v_existing.type,
                v_existing.created_at, v_existing.idempotency_key,
                TRUE AS is_replay,
                COALESCE(v_oasis_growth, 0),
                COALESCE(v_oasis_health, 100),
                COALESCE(v_oasis_streak, 0);
            RETURN;
        END IF;
    END IF;

    -- (guard) Profile must exist — see ProfileNotFoundError in transaction_repo.py.
    IF NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = p_user_id) THEN
        RAISE EXCEPTION 'No profile found for user %', p_user_id
            USING ERRCODE = 'P0004';
    END IF;

    v_signed_amount := CASE WHEN p_type = 'EXPENSE' THEN -p_amount ELSE p_amount END;

    -- (b) Insert the transaction.
    INSERT INTO transactions (user_id, amount, description, category, type, idempotency_key)
    VALUES (p_user_id, p_amount, p_description, p_category, p_type, p_idempotency_key)
    RETURNING * INTO v_txn;

    -- (c) Update the running balance.
    UPDATE profiles
    SET current_balance = current_balance + v_signed_amount
    WHERE id = p_user_id;

    -- (d) Upsert the Oasis state. A "positive action" is any transaction
    -- whose growth_delta is > 0 (currently: a SAVINGS transaction) — that's
    -- what advances the streak. On conflict, the streak either grows by one
    -- (last positive action was yesterday), stays flat (already had one
    -- today, or today wasn't a positive action), or resets to 1 (streak was
    -- broken by a gap of 2+ days).
    v_is_positive_action := p_growth_delta > 0;

    INSERT INTO oasis_states (
        user_id, growth_level, health_score,
        current_streak_days, longest_streak_days,
        last_positive_action_date, updated_at
    )
    VALUES (
        p_user_id,
        GREATEST(0, p_growth_delta),
        GREATEST(0, LEAST(100, 100 + p_health_delta)),
        CASE WHEN v_is_positive_action THEN 1 ELSE 0 END,
        CASE WHEN v_is_positive_action THEN 1 ELSE 0 END,
        CASE WHEN v_is_positive_action THEN CURRENT_DATE ELSE NULL END,
        now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        growth_level = GREATEST(0, oasis_states.growth_level + p_growth_delta),
        health_score = GREATEST(0, LEAST(100, oasis_states.health_score + p_health_delta)),
        current_streak_days = CASE
            WHEN NOT v_is_positive_action THEN oasis_states.current_streak_days
            WHEN oasis_states.last_positive_action_date = CURRENT_DATE THEN oasis_states.current_streak_days
            WHEN oasis_states.last_positive_action_date = CURRENT_DATE - 1 THEN oasis_states.current_streak_days + 1
            ELSE 1
        END,
        longest_streak_days = GREATEST(
            oasis_states.longest_streak_days,
            CASE
                WHEN NOT v_is_positive_action THEN oasis_states.current_streak_days
                WHEN oasis_states.last_positive_action_date = CURRENT_DATE THEN oasis_states.current_streak_days
                WHEN oasis_states.last_positive_action_date = CURRENT_DATE - 1 THEN oasis_states.current_streak_days + 1
                ELSE 1
            END
        ),
        last_positive_action_date = CASE
            WHEN v_is_positive_action THEN CURRENT_DATE
            ELSE oasis_states.last_positive_action_date
        END,
        updated_at = now()
    RETURNING growth_level, health_score, current_streak_days
    INTO v_oasis_growth, v_oasis_health, v_oasis_streak;

    RETURN QUERY SELECT
        v_txn.id, v_txn.user_id, v_txn.amount, v_txn.description, v_txn.category,
        v_txn.type, v_txn.created_at, v_txn.idempotency_key,
        FALSE AS is_replay,
        v_oasis_growth, v_oasis_health, v_oasis_streak;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. get_category_spending_stats — backs the anomaly-detection wildcard
-- -----------------------------------------------------------------------------
-- A single server-side aggregate instead of pulling a user's transaction
-- history into Python to compute mean/stddev there — keeps the "Hackathon
-- Edge" feature (flagging an unusually large spend for its category) cheap
-- enough to run synchronously on every transaction write.
CREATE OR REPLACE FUNCTION get_category_spending_stats(p_user_id UUID, p_category TEXT)
RETURNS TABLE (avg_amount NUMERIC, stddev_amount NUMERIC, sample_size BIGINT)
LANGUAGE sql
STABLE
AS $$
    SELECT
        COALESCE(AVG(amount), 0),
        COALESCE(STDDEV_POP(amount), 0),
        COUNT(*)
    FROM transactions
    WHERE user_id = p_user_id
      AND category = p_category
      AND type = 'EXPENSE';
$$;
