-- =============================================================================
-- Migration 007 — Harden SECURITY DEFINER RPCs with auth.uid() ownership checks
--
-- PURPOSE
-- -------
-- All user-facing RPC functions were previously defined with SECURITY DEFINER
-- and granted only to service_role.  This means they run with definer
-- privileges (bypassing RLS), and ownership was enforced solely by the
-- application-layer `require_matching_user` guard in each route handler.
--
-- This migration adds a defense-in-depth guard INSIDE every SECURITY DEFINER
-- function: if `auth.uid()` is set (i.e., the caller is an authenticated
-- user, not a service-role admin), the function immediately raises a
-- permission-denied error if the caller's UUID does not match the `p_user_id`
-- parameter (or the row owner, for functions that look up by `p_goal_id`).
--
-- The check is intentionally a soft guard: it is skipped when `auth.uid()` IS
-- NULL (service-role or superuser connections, where there is no JWT context).
-- This preserves backward compatibility for any server-side calls that
-- legitimately need elevated access while still blocking cross-user attacks
-- from authenticated clients.
--
-- GRANT CHANGES
-- -------------
-- Grants are moved from `service_role` to `authenticated`:
--   - The new per-user Supabase client (anon key + user JWT) makes calls as
--     the `authenticated` Postgres role — it must be granted execution rights.
--   - service_role does NOT need an explicit GRANT; it already has superuser
--     privileges and can execute any function.
--
-- Run via the Supabase Dashboard → SQL editor, or `supabase db push`.
-- Safe to run more than once: every function uses CREATE OR REPLACE.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. create_transaction_atomic
--    Current signature: migration 005 (TEXT params, idempotency, Oasis deltas)
-- ---------------------------------------------------------------------------
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
    -- ── Ownership guard ───────────────────────────────────────────────────
    -- When called via an authenticated user's JWT (anon-key client), auth.uid()
    -- is the caller's UUID. Reject the call if it doesn't match p_user_id.
    -- Skip the check for service-role/superuser calls (auth.uid() IS NULL).
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'permission denied: caller % cannot act as user %',
            auth.uid(), p_user_id
            USING ERRCODE = '42501';  -- insufficient_privilege
    END IF;

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
        p_category::category_type,
        p_type::transaction_type,
        p_idempotency_key
    )
    RETURNING * INTO v_txn;

    -- (c) Update running balance
    UPDATE profiles
    SET current_balance = current_balance + v_signed_amount
    WHERE id = p_user_id;

    -- (d) Upsert Oasis state
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

-- Revoke old service_role-only grant and grant to authenticated instead.
REVOKE EXECUTE ON FUNCTION public.create_transaction_atomic(
    UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC
) FROM service_role;

GRANT EXECUTE ON FUNCTION public.create_transaction_atomic(
    UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC
) TO authenticated;


-- ---------------------------------------------------------------------------
-- 2. create_goal_atomic
--    Current signature: migration 003 (category_type enum, date deadline)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_goal_atomic(
    p_user_id      UUID,
    p_title        TEXT,
    p_target_amount NUMERIC,
    p_category     category_type,
    p_deadline     DATE
)
RETURNS public.goals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_id UUID;
    v_new_goal    public.goals;
BEGIN
    -- ── Ownership guard ───────────────────────────────────────────────────
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'permission denied: caller % cannot act as user %',
            auth.uid(), p_user_id
            USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_existing_id
    FROM public.goals
    WHERE user_id = p_user_id AND status = 'ACTIVE'
    FOR UPDATE;

    IF v_existing_id IS NOT NULL THEN
        RAISE EXCEPTION 'ACTIVE_GOAL_EXISTS: user % already has active goal %',
            p_user_id, v_existing_id
            USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO public.goals (user_id, title, target_amount, saved_amount, category, deadline, status)
    VALUES (p_user_id, p_title, p_target_amount, 0.0, p_category, p_deadline, 'ACTIVE')
    RETURNING * INTO v_new_goal;

    RETURN v_new_goal;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_goal_atomic(UUID, TEXT, NUMERIC, category_type, DATE)
    FROM service_role;

GRANT EXECUTE ON FUNCTION public.create_goal_atomic(UUID, TEXT, NUMERIC, category_type, DATE)
    TO authenticated;


-- ---------------------------------------------------------------------------
-- 3. transition_goal_status
--    Current signature: migration 003 (goal_status enum)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transition_goal_status(
    p_goal_id   UUID,
    p_user_id   UUID,
    p_new_status goal_status
)
RETURNS public.goals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_goal public.goals;
BEGIN
    -- ── Ownership guard ───────────────────────────────────────────────────
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'permission denied: caller % cannot act as user %',
            auth.uid(), p_user_id
            USING ERRCODE = '42501';
    END IF;

    IF p_new_status NOT IN ('COMPLETED', 'ARCHIVED') THEN
        RAISE EXCEPTION 'INVALID_STATUS_TRANSITION: % is not a legal target status',
            p_new_status
            USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_goal
    FROM public.goals
    WHERE id = p_goal_id AND user_id = p_user_id
    FOR UPDATE;

    IF v_goal.id IS NULL THEN
        RAISE EXCEPTION 'GOAL_NOT_FOUND: % for user %', p_goal_id, p_user_id
            USING ERRCODE = 'P0002';
    END IF;

    IF v_goal.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'GOAL_NOT_ACTIVE: goal % is already %', p_goal_id, v_goal.status
            USING ERRCODE = 'P0003';
    END IF;

    UPDATE public.goals
    SET status = p_new_status
    WHERE id = p_goal_id
    RETURNING * INTO v_goal;

    RETURN v_goal;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.transition_goal_status(UUID, UUID, goal_status)
    FROM service_role;

GRANT EXECUTE ON FUNCTION public.transition_goal_status(UUID, UUID, goal_status)
    TO authenticated;


-- ---------------------------------------------------------------------------
-- 4. increment_goal_progress
--    Current signature: migration 003 (p_goal_id only — no p_user_id)
--    Ownership check: verify the goal's user_id matches auth.uid()
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.increment_goal_progress(
    p_goal_id UUID,
    p_amount  NUMERIC
)
RETURNS public.goals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_goal public.goals;
BEGIN
    -- ── Ownership guard ───────────────────────────────────────────────────
    -- increment_goal_progress has no p_user_id parameter, so we look up the
    -- goal's owner and compare against auth.uid().
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.goals
            WHERE id = p_goal_id AND user_id = auth.uid()
        ) THEN
            RAISE EXCEPTION 'permission denied: goal % does not belong to caller %',
                p_goal_id, auth.uid()
                USING ERRCODE = '42501';
        END IF;
    END IF;

    UPDATE public.goals
    SET saved_amount = saved_amount + p_amount,
        status = CASE
            WHEN saved_amount + p_amount >= target_amount THEN 'COMPLETED'
            ELSE status
        END
    WHERE id = p_goal_id AND status = 'ACTIVE'
    RETURNING * INTO v_goal;

    IF v_goal.id IS NULL THEN
        RAISE EXCEPTION 'GOAL_NOT_FOUND_OR_INACTIVE: %', p_goal_id
            USING ERRCODE = 'P0002';
    END IF;

    RETURN v_goal;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.increment_goal_progress(UUID, NUMERIC)
    FROM service_role;

GRANT EXECUTE ON FUNCTION public.increment_goal_progress(UUID, NUMERIC)
    TO authenticated;


-- ---------------------------------------------------------------------------
-- 5. get_category_spending_stats
--    Current signature: migration 002 (LANGUAGE sql STABLE)
--    Add ownership guard as an inline WHERE clause filter.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_category_spending_stats(
    p_user_id UUID,
    p_category TEXT
)
RETURNS TABLE (avg_amount NUMERIC, stddev_amount NUMERIC, sample_size BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        COALESCE(AVG(amount), 0),
        COALESCE(STDDEV_POP(amount), 0),
        COUNT(*)
    FROM transactions
    WHERE user_id = p_user_id
      -- Ownership guard: when called as an authenticated user, verify the
      -- caller matches p_user_id. auth.uid() is NULL for service-role calls,
      -- so the guard is a no-op there (the explicit user_id filter still
      -- restricts the result set to the requested user's rows).
      AND (auth.uid() IS NULL OR auth.uid() = p_user_id)
      AND category = p_category
      AND type = 'EXPENSE';
$$;

-- get_category_spending_stats previously had no explicit grant; add one.
GRANT EXECUTE ON FUNCTION public.get_category_spending_stats(UUID, TEXT)
    TO authenticated;
