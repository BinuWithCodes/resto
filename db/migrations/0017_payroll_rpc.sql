-- ============================================================================
-- Migration 0017 — Payroll RPCs (§4.4): run_payroll (draft) + approve_payroll
--
-- SECURITY INVOKER; org is read from the RLS-filtered organizations table (the
-- select policy returns only the caller's org), so no direct `private` calls.
--
-- run_payroll builds a draft run + one payroll_item per active employee, with
-- net = gross − unpaid-leave deduction − advance instalment (+ OT/bonus, left 0
-- for manual entry on the draft), mirroring lib/money.ts payrollNetPaise. It
-- records an advance_deductions row per applied instalment. A second run for the
-- same period is rejected (no duplicate runs).
--
-- approve_payroll flips draft -> approved (super_admin-gated by the
-- enforce_payroll_approval trigger, 0011) and locks that period's attendance.
-- ============================================================================

-- ---- run_payroll -----------------------------------------------------------
create or replace function public.run_payroll(
  p_period       text,
  p_working_days integer,
  p_scope        text default 'all'
) returns public.payroll_runs
language plpgsql
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_org       uuid;
  v_run       public.payroll_runs;
  v_from      date;
  v_to        date;
  v_emp       record;
  v_adv       record;
  v_item_id   uuid;
  v_gross     bigint;
  v_unpaid    numeric(5,1);
  v_perday    bigint;
  v_leave_ded bigint;
  v_adv_ded   bigint;
  v_inst      bigint;
  v_take      bigint;
  v_adv_ids   uuid[];
  v_adv_amts  bigint[];
  i           integer;
begin
  if p_working_days is null or p_working_days <= 0 then
    raise exception 'working days must be greater than zero' using errcode = '22023';
  end if;

  select id into v_org from public.organizations limit 1;
  if v_org is null then
    raise exception 'no accessible organization' using errcode = 'P0002';
  end if;

  perform 1 from public.payroll_runs where org_id = v_org and period = p_period;
  if found then
    raise exception 'a payroll run for % already exists', p_period using errcode = 'P0001';
  end if;

  v_from := to_date(p_period || '-01', 'YYYY-MM-DD');
  v_to   := (v_from + interval '1 month')::date - 1;

  insert into public.payroll_runs (org_id, period, scope, status, created_by)
  values (v_org, p_period, p_scope, 'draft', v_uid)
  returning * into v_run;

  for v_emp in
    select * from public.employees where org_id = v_org and status = 'active'
  loop
    v_gross := v_emp.monthly_salary_paise;

    -- unpaid, approved leave days overlapping the period
    select coalesce(sum(days), 0) into v_unpaid
    from public.leaves
    where employee_id = v_emp.id and unpaid = true and status = 'approved'
      and from_date <= v_to and to_date >= v_from;

    v_perday    := round(v_gross::numeric / p_working_days)::bigint;
    v_leave_ded := (v_perday * v_unpaid)::bigint;

    -- advance instalments: one instalment per approved advance with a balance
    v_adv_ded  := 0;
    v_adv_ids  := '{}';
    v_adv_amts := '{}';
    for v_adv in
      select a.id, a.amount_paise, a.instalments,
             a.amount_paise
               - coalesce((select sum(amount_paise) from public.advance_deductions
                           where advance_id = a.id), 0) as outstanding
      from public.advances a
      where a.employee_id = v_emp.id and a.status = 'approved'
    loop
      if v_adv.outstanding <= 0 then
        continue;
      end if;
      v_inst := round(v_adv.amount_paise::numeric / v_adv.instalments)::bigint;
      v_take := least(v_inst, v_adv.outstanding);
      v_adv_ded  := v_adv_ded + v_take;
      v_adv_ids  := array_append(v_adv_ids, v_adv.id);
      v_adv_amts := array_append(v_adv_amts, v_take);
    end loop;

    insert into public.payroll_items
      (org_id, run_id, employee_id, gross_paise, leave_deduction_paise,
       advance_deduction_paise, ot_paise, bonus_paise, net_paise)
    values
      (v_org, v_run.id, v_emp.id, v_gross, v_leave_ded, v_adv_ded, 0, 0,
       v_gross - v_leave_ded - v_adv_ded)
    returning id into v_item_id;

    if array_length(v_adv_ids, 1) is not null then
      for i in 1 .. array_length(v_adv_ids, 1) loop
        insert into public.advance_deductions
          (org_id, advance_id, payroll_item_id, amount_paise, deducted_on)
        values
          (v_org, v_adv_ids[i], v_item_id, v_adv_amts[i], v_from);
      end loop;
    end if;
  end loop;

  return v_run;
end $$;

-- ---- approve_payroll -------------------------------------------------------
create or replace function public.approve_payroll(p_run_id uuid)
returns public.payroll_runs
language plpgsql
as $$
declare
  v_run  public.payroll_runs;
  v_uid  uuid := (select auth.uid());
  v_from date;
  v_to   date;
begin
  select * into v_run from public.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'payroll run not found or not accessible' using errcode = 'P0002';
  end if;
  if v_run.status <> 'draft' then
    raise exception 'payroll run is already approved' using errcode = 'P0001';
  end if;

  v_from := to_date(v_run.period || '-01', 'YYYY-MM-DD');
  v_to   := (v_from + interval '1 month')::date - 1;

  -- status -> approved is super_admin-gated by the trigger (raises 42501 for admin).
  update public.payroll_runs set status = 'approved', approved_by = v_uid
  where id = p_run_id
  returning * into v_run;

  -- lock this period's attendance for the run's employees (§4.4)
  update public.attendance set locked = true
  where att_date between v_from and v_to
    and employee_id in (select employee_id from public.payroll_items where run_id = p_run_id)
    and not locked;

  return v_run;
end $$;

grant execute on function public.run_payroll(text, integer, text) to authenticated;
grant execute on function public.approve_payroll(uuid) to authenticated;
