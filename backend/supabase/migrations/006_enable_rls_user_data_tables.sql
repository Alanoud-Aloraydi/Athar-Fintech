-- =============================================================================
-- Migration 006 — Enable Row Level Security on all user-data tables
--
-- PURPOSE
-- -------
-- The backend previously used the Supabase service-role key for every
-- database operation. The service-role key bypasses RLS entirely, meaning
-- the sole access-control layer was the application-level
-- `require_matching_user` guard in each route handler. If that guard is
-- ever missed (new endpoint, refactor, type-coercion edge case) an
-- authenticated user could reach any other user's data at the database
-- level with no fallback.
--
-- This migration adds the database-layer fallback:
--   1. RLS is enabled on every table that holds user-owned rows.
--   2. A policy restricts authenticated users to their own rows.
--   3. The service_role role is explicitly granted a bypass policy so
--      server-side admin/write operations (balance updates, oasis upserts,
--      etc.) continue to work. Per-user reads are now done via a user-
--      scoped client (anon key + user JWT), which DOES respect RLS.
--
-- These policies are additive: they do not change any existing data or
-- index, and are safe to run on a live database.
--
-- Run via the Supabase Dashboard → SQL editor, or `supabase db push`.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

-- Authenticated users may read and write only their own transaction rows.
CREATE POLICY "transactions_owner_access"
    ON public.transactions
    FOR ALL
    TO authenticated
    USING  (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- The service_role key must continue to bypass RLS so backend writes
-- (balance updates, idempotency checks, etc.) are never blocked.
CREATE POLICY "transactions_service_role_bypass"
    ON public.transactions
    FOR ALL
    TO service_role
    USING  (true)
    WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- goals
-- ---------------------------------------------------------------------------
ALTER TABLE public.goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "goals_owner_access"
    ON public.goals
    FOR ALL
    TO authenticated
    USING  (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "goals_service_role_bypass"
    ON public.goals
    FOR ALL
    TO service_role
    USING  (true)
    WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Note: the profiles primary key is `id` (= the auth.users UUID), not
-- `user_id`, hence the different column name in the USING clause.
CREATE POLICY "profiles_owner_access"
    ON public.profiles
    FOR ALL
    TO authenticated
    USING  (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_service_role_bypass"
    ON public.profiles
    FOR ALL
    TO service_role
    USING  (true)
    WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- oasis_states
-- ---------------------------------------------------------------------------
ALTER TABLE public.oasis_states ENABLE ROW LEVEL SECURITY;

CREATE POLICY "oasis_states_owner_access"
    ON public.oasis_states
    FOR ALL
    TO authenticated
    USING  (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "oasis_states_service_role_bypass"
    ON public.oasis_states
    FOR ALL
    TO service_role
    USING  (true)
    WITH CHECK (true);
