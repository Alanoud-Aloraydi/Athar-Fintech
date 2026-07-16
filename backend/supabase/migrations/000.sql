-- =============================================================================
-- Athar-Fintech — Transaction ingestion + balance integrity function
--
-- Replaces a plain `insert into transactions` with a single atomic
-- operation that also updates `profiles.current_balance`, so the two
-- writes cannot lose a race under concurrent transactions for the same
-- user (see create_transaction_atomic below).
--
-- Business rule: Athar mirrors real-world financial behavior rather
-- than gatekeeping it — current_balance is allowed to go negative.
-- This function never rejects an insert for insufficient balance; it
-- only ever records what actually happened.
--
-- Run this after schema.sql, fix_grants.sql, and goal_lifecycle_functions.sql.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- create_transaction_atomic
--
-- Locks the user's profile row (SELECT ... FOR UPDATE) before touching
-- it, so two concurrent transactions for the same user serialize on the
-- balance update instead of both reading the same starting balance and
-- one overwriting the other's contribution (the same class of
-- lost-update race increment_goal_progress fixes for goals). The lock
-- is held for the duration of this function call, which also spans the
-- transaction insert, so the insert and the balance update commit
-- together or not at all.
-- -----------------------------------------------------------------------------
create or replace function public.create_transaction_atomic(
    p_user_id uuid,
    p_amount numeric,
    p_description text,
    p_category category_type,
    p_type transaction_type
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
    v_transaction public.transactions;
    v_balance_delta numeric;
begin
    perform 1 from public.profiles where id = p_user_id for update;

    if not found then
        raise exception 'PROFILE_NOT_FOUND: %', p_user_id
            using errcode = 'P0004';
    end if;

    insert into public.transactions (user_id, amount, description, category, type)
    values (p_user_id, p_amount, p_description, p_category, p_type)
    returning * into v_transaction;

    -- EXPENSE decreases the balance, INCOME increases it. No floor at
    -- zero: current_balance is allowed to go negative by design, since
    -- this platform tracks real spending behavior rather than gating it.
    v_balance_delta := case p_type
        when 'INCOME' then p_amount
        when 'EXPENSE' then -p_amount
        else 0
    end;

    update public.profiles
    set current_balance = current_balance + v_balance_delta
    where id = p_user_id;

    return v_transaction;
end;
$$;

grant execute on function public.create_transaction_atomic(
    uuid, numeric, text, category_type, transaction_type
) to service_role;