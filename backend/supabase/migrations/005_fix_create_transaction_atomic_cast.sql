-- =============================================================================
-- Migration 005 — Fix create_transaction_atomic: cast TEXT params to enum types
--
-- Migration 002 changed p_category and p_type from enum to TEXT to allow
-- the Supabase PostgREST RPC endpoint to pass arbitrary string values.
-- However the INSERT inside the function body was not updated to include
-- explicit casts (::category_type, ::transaction_type), causing Postgres
-- error 42804 on every call.
--
-- This migration is a DROP + CREATE OR REPLACE of the same function with
-- the only change being the two explicit casts on the INSERT line.
-- It is idempotent (safe to run more than once).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_transaction_atomic(
    p_user_id          UUID,
    p_amount           NUMERIC,
    p_description      TEXT,
    p_category         TEXT,
    p_type             TEXT,
    p_idempotency_key  TEXT    DEFAULT NULL,
    p_growth_delta     NUMERIC DEFAULT 0,
    p_health_delta     NUMERIC DEFAULT 0
)
RETURNS TABLE (
    id                  UUID,
    user_id             UUID,
    amount              NUMERIC,
    description         TEXT,
    category            TEXT,
    type                TEXT,
    created_at          TIMESTAMPTZ,
    idempotency_key     TEXT,
    is_replay           BOOLEAN,
    oasis_growth_level  NUMERIC,
    oasis_health_score  NUMERIC,
    oasis_streak_days   INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing          transactions%ROWTYPE;
    v_txn               transactions%ROWTYPE;
    v_signed_amount     NUMERIC;
    v_is_positive_action BOOLEAN;
    v_oasis_growth      NUMERIC;
    v_oasis_health      NUMERIC;
    v_oasis_streak      INT;
BEGIN
    -- (a) Idempotent replay short-circuit
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
                v_existing.description,
                v_existing.category::TEXT, v_existing.type::TEXT,
                v_existing.created_at, v_existing.idempotency_key,
                TRUE AS is_replay,
                COALESCE(v_oasis_growth, 0),
                COALESCE(v_oasis_health, 100),
                COALESCE(v_oasis_streak, 0);
            RETURN;
        END IF;
    END IF;

    -- (guard) Profile must exist
    IF NOT EXISTS (SELECT 1 FROM profiles p WHERE p.id = p_user_id) THEN
        RAISE EXCEPTION 'No profile found for user %', p_user_id
            USING ERRCODE = 'P0004';
    END IF;

    v_signed_amount := CASE WHEN p_type = 'EXPENSE' THEN -p_amount ELSE p_amount END;

    -- (b) Insert transaction — cast TEXT → enum explicitly
    INSERT INTO transactions (user_id, amount, description, category, type, idempotency_key)
    VALUES (
        p_user_id,
        p_amount,
        p_description,
        p_category::category_type,        -- ← FIX: was missing cast
        p_type::transaction_type,         -- ← FIX: was missing cast
        p_idempotency_key
    )
    RETURNING * INTO v_txn;

    -- (c) Update running balance
    UPDATE profiles
    SET current_balance = current_balance + v_signed_amount
    WHERE id = p_user_id;

    -- (d) Upsert Oasis state (streak logic unchanged from migration 002)
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
            WHEN oasis_states.last_positive_action_date = CURRENT_DATE
                THEN oasis_states.current_streak_days
            WHEN oasis_states.last_positive_action_date = CURRENT_DATE - 1
                THEN oasis_states.current_streak_days + 1
            ELSE 1
        END,
        longest_streak_days = GREATEST(
            oasis_states.longest_streak_days,
            CASE
                WHEN NOT v_is_positive_action THEN oasis_states.current_streak_days
                WHEN oasis_states.last_positive_action_date = CURRENT_DATE
                    THEN oasis_states.current_streak_days
                WHEN oasis_states.last_positive_action_date = CURRENT_DATE - 1
                    THEN oasis_states.current_streak_days + 1
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
        v_txn.id, v_txn.user_id, v_txn.amount, v_txn.description,
        v_txn.category::TEXT, v_txn.type::TEXT,
        v_txn.created_at, v_txn.idempotency_key,
        FALSE AS is_replay,
        v_oasis_growth, v_oasis_health, v_oasis_streak;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_transaction_atomic(
    UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC
) TO service_role;
