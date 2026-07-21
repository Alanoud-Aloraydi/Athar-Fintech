-- =============================================================================
-- Migration 008 — Grant the `authenticated` role the table privileges it needs
--
-- WHY
-- ---
-- Migrations 006/007 enabled RLS and moved the backend to a per-user Supabase
-- client (anon key + user JWT), which runs as the `authenticated` Postgres
-- role. But two table grants were never added, so per-user access is denied at
-- the GRANT layer (before RLS policies are even evaluated):
--
--   • profiles      — `authenticated` had SELECT/UPDATE (migration 001) but not
--                     INSERT, which ProfileRepository.ensure_profile needs for
--                     its upsert. Result: the dashboard 502s on first load.
--   • oasis_states  — created in migration 002, AFTER the grants in migration
--                     001, so `authenticated` had no privileges on it at all.
--
-- RLS policies restricting rows to `auth.uid()` already exist (migration 006),
-- so these grants only ever expose a user's OWN rows.
--
-- Safe to run more than once. Run via Supabase Dashboard → SQL editor.
-- (The backend also works without this migration: profiles/oasis access falls
--  back to the service-role client — see app/presentation/dependencies.py.
--  Apply this if you prefer those two tables to stay on the per-user client.)
-- =============================================================================

-- Make sure RLS + owner/service policies are present (idempotent).
ALTER TABLE public.profiles     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.oasis_states ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_owner_access" ON public.profiles;
CREATE POLICY "profiles_owner_access"
    ON public.profiles
    FOR ALL
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_service_role_bypass" ON public.profiles;
CREATE POLICY "profiles_service_role_bypass"
    ON public.profiles
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "oasis_states_owner_access" ON public.oasis_states;
CREATE POLICY "oasis_states_owner_access"
    ON public.oasis_states
    FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "oasis_states_service_role_bypass" ON public.oasis_states;
CREATE POLICY "oasis_states_service_role_bypass"
    ON public.oasis_states
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- The actual fix: the missing table grants.
GRANT INSERT                 ON public.profiles     TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.oasis_states TO authenticated;
