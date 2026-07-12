-- ============================================================================
-- Migration 0013 — Shift close + lock as transactional RPCs (§4.4)
-- Multi-table money writes run as one Postgres function (one transaction).
-- SECURITY INVOKER so the caller's RLS applies to every statement — an admin can
-- only close/lock sessions at their own locations. Cash reconciliation:
-- expected = opening + cash income − cash expense; a non-zero variance requires
-- a reason. Close moves open→closed; lock moves closed→locked.
-- ============================================================================

create or replace function public.close_shift(
  p_session_id     uuid,
  p_actual_cash    bigint,
  p_variance_reason text default null,
  p_handover_note  text default null
) returns public.shift_sessions
language plpgsql
as $$
declare
  v_session      public.shift_sessions;
  v_cash_income  bigint;
  v_cash_expense bigint;
  v_expected     bigint;
  v_variance     bigint;
begin
  if p_actual_cash < 0 then
    raise exception 'actual cash cannot be negative' using errcode = '23514';
  end if;

  -- RLS-checked read + row lock; not-found also covers no-access (invisible row)
  select * into v_session from public.shift_sessions where id = p_session_id for update;
  if not found then
    raise exception 'shift session not found or not accessible' using errcode = 'P0002';
  end if;
  if v_session.status <> 'open' then
    raise exception 'shift is not open' using errcode = 'P0001';
  end if;

  select coalesce(sum(amount_paise), 0) into v_cash_income
  from public.shift_income_entries where session_id = p_session_id and mode = 'cash';
  select coalesce(sum(amount_paise), 0) into v_cash_expense
  from public.shift_expense_entries where session_id = p_session_id and mode = 'cash';

  v_expected := v_session.opening_cash_paise + v_cash_income - v_cash_expense;
  v_variance := p_actual_cash - v_expected;

  if v_variance <> 0 and (p_variance_reason is null or length(trim(p_variance_reason)) = 0) then
    raise exception 'variance reason is required when cash does not reconcile'
      using errcode = 'P0001';
  end if;

  update public.shift_sessions set
    status                      = 'closed',
    actual_closing_cash_paise   = p_actual_cash,
    expected_closing_cash_paise = v_expected,
    variance_paise              = v_variance,
    variance_reason             = p_variance_reason,
    handover_note               = p_handover_note,
    closed_by                   = (select auth.uid()),
    closed_at                   = now()
  where id = p_session_id
  returning * into v_session;

  return v_session;
end $$;

create or replace function public.lock_shift(p_session_id uuid)
returns public.shift_sessions
language plpgsql
as $$
declare
  v_session public.shift_sessions;
begin
  update public.shift_sessions set status = 'locked'
  where id = p_session_id and status = 'closed'
  returning * into v_session;

  if not found then
    raise exception 'shift must be closed before locking (or not accessible)'
      using errcode = 'P0001';
  end if;
  return v_session;
end $$;

grant execute on function public.close_shift(uuid, bigint, text, text) to authenticated;
grant execute on function public.lock_shift(uuid) to authenticated;
