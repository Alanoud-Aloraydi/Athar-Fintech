-- =============================================================================
-- Athar-Fintech — grants fix + debug helper
--
-- Run this against the same project as schema.sql. Fixes "permission
-- denied for table X" errors that BYPASSRLS does NOT fix, because
-- BYPASSRLS only skips row-level security policies — it does not grant
-- base object access. Roles still need explicit GRANTs on every table.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Debug helper — call this from the app to prove which Postgres role a
-- given API key is actually executing as. PostgREST (which the
-- supabase-py client talks to) connects as an `authenticator` role and
-- then does `SET LOCAL ROLE` per-request based on which key/JWT was
-- sent — `current_user` reflects that switched-to role; `session_user`
-- stays as the original login (authenticator).
-- -----------------------------------------------------------------------------
create or replace function public.debug_whoami()
returns table (current_role_name text, session_role_name text)
language sql
security invoker
as $$
    select current_user::text, session_user::text;
$$;

grant execute on function public.debug_whoami() to service_role, authenticated, anon;


-- -----------------------------------------------------------------------------
-- Explicit grants — the actual fix.
--
-- Schema-level USAGE is a prerequisite for any table access at all.
-- -----------------------------------------------------------------------------
grant usage on schema public to service_role, authenticated, anon;

-- service_role: full access to everything, matching its role as the
-- backend's server-side, RLS-bypassing connection.
grant select, insert, update, delete on public.profiles, public.goals, public.transactions
    to service_role;
grant usage on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- authenticated / anon: grants scoped to match the RLS policies already
-- defined in schema.sql — a grant without a matching policy is useless,
-- and a policy without a matching grant is exactly the bug you just hit,
-- so these need to move together.
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.goals to authenticated;
grant select, insert on public.transactions to authenticated;

-- -----------------------------------------------------------------------------
-- Make this durable for any table created *after* this point, so the
-- same bug can't resurface the next time a table is added.
-- -----------------------------------------------------------------------------
alter default privileges in schema public
    grant all on tables to service_role;
alter default privileges in schema public
    grant usage, select on sequences to service_role;
alter default privileges in schema public
    grant execute on functions to service_role;