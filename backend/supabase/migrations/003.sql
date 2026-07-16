-- =============================================================================
-- Athar-Fintech — Goal Lifecycle integrity functions
--
-- Replaces two unsafe application-level patterns with single-statement,
-- atomic database operations:
--
--   1. "check for an active goal, then insert a new one" (TOCTOU race
--      across two network round-trips) -> create_goal_atomic()
--   2. "fetch saved_amount, add in Python, write the sum back"
--      (lost-update race under concurrent transactions) -> increment_goal_progress()
--
-- Run this after schema.sql and fix_grants.sql.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- create_goal_atomic
--
-- Locks any existing ACTIVE goal row for the user (SELECT ... FOR UPDATE)
-- before checking it, so two concurrent calls for the same user cannot
-- interleave between the check and the insert. If no ACTIVE goal exists
-- for *either* concurrent caller (nothing to lock), the pre-existing
-- partial unique index `uq_goals_one_active_per_user` is the backstop —
-- one insert succeeds, the other raises a 23505 unique_violation, which
-- the repository maps to the same GoalConflictError as the explicit
-- P0001 case below. Defense in depth, not redundant: the row lock
-- closes the common case cleanly; the index guarantees correctness even
-- in the case the lock can't cover.
-- -----------------------------------------------------------------------------
create or replace function public.create_goal_atomic(
    p_user_id uuid,
    p_title text,
    p_target_amount numeric,
    p_category category_type,
    p_deadline date
)
returns public.goals
language plpgsql
security definer
set search_path = public
as $$
declare
    v_existing_id uuid;
    v_new_goal public.goals;
begin
    select id into v_existing_id
    from public.goals
    where user_id = p_user_id and status = 'ACTIVE'
    for update;

    if v_existing_id is not null then
        raise exception 'ACTIVE_GOAL_EXISTS: user % already has active goal %', p_user_id, v_existing_id
            using errcode = 'P0001';
    end if;

    insert into public.goals (user_id, title, target_amount, saved_amount, category, deadline, status)
    values (p_user_id, p_title, p_target_amount, 0.0, p_category, p_deadline, 'ACTIVE')
    returning * into v_new_goal;

    return v_new_goal;
end;
$$;

grant execute on function public.create_goal_atomic(uuid, text, numeric, category_type, date)
    to service_role;


-- -----------------------------------------------------------------------------
-- transition_goal_status
--
-- The only sanctioned way to move a goal out of ACTIVE. Locks the target
-- row, verifies ownership and that it's currently ACTIVE (only ACTIVE ->
-- COMPLETED/ARCHIVED is a legal transition in this MVP; there is no path
-- back to ACTIVE from a terminal state), then updates it.
-- -----------------------------------------------------------------------------
create or replace function public.transition_goal_status(
    p_goal_id uuid,
    p_user_id uuid,
    p_new_status goal_status
)
returns public.goals
language plpgsql
security definer
set search_path = public
as $$
declare
    v_goal public.goals;
begin
    if p_new_status not in ('COMPLETED', 'ARCHIVED') then
        raise exception 'INVALID_STATUS_TRANSITION: % is not a legal target status', p_new_status
            using errcode = 'P0001';
    end if;

    select * into v_goal
    from public.goals
    where id = p_goal_id and user_id = p_user_id
    for update;

    if v_goal.id is null then
        raise exception 'GOAL_NOT_FOUND: % for user %', p_goal_id, p_user_id
            using errcode = 'P0002';
    end if;

    if v_goal.status <> 'ACTIVE' then
        raise exception 'GOAL_NOT_ACTIVE: goal % is already %', p_goal_id, v_goal.status
            using errcode = 'P0003';
    end if;

    update public.goals
    set status = p_new_status
    where id = p_goal_id
    returning * into v_goal;

    return v_goal;
end;
$$;

grant execute on function public.transition_goal_status(uuid, uuid, goal_status)
    to service_role;


-- -----------------------------------------------------------------------------
-- increment_goal_progress
--
-- Atomically adds p_amount to saved_amount in a single UPDATE (no
-- read-then-write round trip, so no lost-update race), and auto-completes
-- the goal in the same statement if the new total reaches target_amount.
-- Only matches a row that is currently ACTIVE, so a goal that completed
-- or was archived between the caller's lookup and this call is not
-- silently over-funded.
-- -----------------------------------------------------------------------------
create or replace function public.increment_goal_progress(
    p_goal_id uuid,
    p_amount numeric
)
returns public.goals
language plpgsql
security definer
set search_path = public
as $$
declare
    v_goal public.goals;
begin
    update public.goals
    set saved_amount = saved_amount + p_amount,
        status = case
            when saved_amount + p_amount >= target_amount then 'COMPLETED'
            else status
        end
    where id = p_goal_id and status = 'ACTIVE'
    returning * into v_goal;

    if v_goal.id is null then
        raise exception 'GOAL_NOT_FOUND_OR_INACTIVE: %', p_goal_id
            using errcode = 'P0002';
    end if;

    return v_goal;
end;
$$;

grant execute on function public.increment_goal_progress(uuid, numeric)
    to service_role;
    