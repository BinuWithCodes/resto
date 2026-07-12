-- ============================================================================
-- Migration 0011 — Leave, advances, payroll (Phase 3). Org-scoped.
-- Approvals are super_admin-only (§1.1): payroll run approval, advance approval.
-- Payroll items lock once their run is approved (§4.4). All enforced by triggers.
-- ============================================================================

create type public.leave_status   as enum ('requested', 'approved', 'rejected');
create type public.advance_status as enum ('requested', 'approved', 'paid');
create type public.payroll_status as enum ('draft', 'approved', 'locked');

-- ---- leave_types (org config) ----------------------------------------------
create table public.leave_types (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  name         text not null,
  annual_quota integer not null default 0 check (annual_quota >= 0),
  is_paid      boolean not null default true,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (org_id, name)
);
create index idx_leave_types_org_id on public.leave_types(org_id);

-- ---- leave_balances --------------------------------------------------------
create table public.leave_balances (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references public.organizations(id) on delete cascade,
  employee_id    uuid not null references public.employees(id) on delete cascade,
  leave_type_id  uuid not null references public.leave_types(id) on delete cascade,
  year           integer not null,
  allocated_days numeric(5, 1) not null default 0,
  used_days      numeric(5, 1) not null default 0,
  unique (employee_id, leave_type_id, year)
);
create index idx_leave_balances_employee_id on public.leave_balances(employee_id);
create index idx_leave_balances_org_id on public.leave_balances(org_id);

-- ---- leaves ----------------------------------------------------------------
create table public.leaves (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.organizations(id) on delete cascade,
  employee_id   uuid not null references public.employees(id) on delete cascade,
  leave_type_id uuid references public.leave_types(id) on delete set null,
  from_date     date not null,
  to_date       date not null,
  days          numeric(5, 1) not null default 0 check (days >= 0),
  status        public.leave_status not null default 'requested',
  unpaid        boolean not null default false,
  approved_by   uuid references public.users(id),
  created_by    uuid references public.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index idx_leaves_employee_id on public.leaves(employee_id);
create index idx_leaves_org_id on public.leaves(org_id);

-- ---- advances --------------------------------------------------------------
create table public.advances (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  amount_paise bigint not null check (amount_paise >= 0),
  reason      text,
  status      public.advance_status not null default 'requested',
  instalments integer not null default 1 check (instalments >= 1),
  approved_by uuid references public.users(id),
  created_by  uuid references public.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_advances_employee_id on public.advances(employee_id);
create index idx_advances_org_id on public.advances(org_id);

-- ---- payroll_runs ----------------------------------------------------------
create table public.payroll_runs (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  period      text not null,
  scope       text not null default 'all',
  status      public.payroll_status not null default 'draft',
  approved_by uuid references public.users(id),
  created_by  uuid references public.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_payroll_runs_org_id on public.payroll_runs(org_id);

-- ---- payroll_items ---------------------------------------------------------
create table public.payroll_items (
  id                      uuid primary key default gen_random_uuid(),
  org_id                  uuid not null references public.organizations(id) on delete cascade,
  run_id                  uuid not null references public.payroll_runs(id) on delete cascade,
  employee_id             uuid not null references public.employees(id) on delete restrict,
  gross_paise             bigint not null default 0 check (gross_paise >= 0),
  leave_deduction_paise   bigint not null default 0 check (leave_deduction_paise >= 0),
  advance_deduction_paise bigint not null default 0 check (advance_deduction_paise >= 0),
  ot_paise                bigint not null default 0 check (ot_paise >= 0),
  bonus_paise             bigint not null default 0 check (bonus_paise >= 0),
  net_paise               bigint not null default 0,
  paid_marked             boolean not null default false,
  paid_at                 timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (run_id, employee_id)
);
create index idx_payroll_items_run_id on public.payroll_items(run_id);
create index idx_payroll_items_employee_id on public.payroll_items(employee_id);
create index idx_payroll_items_org_id on public.payroll_items(org_id);

-- ---- advance_deductions ----------------------------------------------------
create table public.advance_deductions (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  advance_id      uuid not null references public.advances(id) on delete cascade,
  payroll_item_id uuid references public.payroll_items(id) on delete set null,
  amount_paise    bigint not null check (amount_paise >= 0),
  deducted_on     date not null default current_date,
  created_at      timestamptz not null default now()
);
create index idx_advance_deductions_advance_id on public.advance_deductions(advance_id);
create index idx_advance_deductions_org_id on public.advance_deductions(org_id);

-- ============================================================================
-- Approval + lock enforcement (super_admin, §1.1/§4.4)
-- ============================================================================
create or replace function private.enforce_payroll_approval()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status in ('approved', 'locked')
     and old.status is distinct from new.status
     and not private.is_super_admin() then
    raise exception 'payroll approval requires super_admin' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger payroll_approval_guard before update on public.payroll_runs
  for each row execute function private.enforce_payroll_approval();

create or replace function private.enforce_advance_approval()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved'
     and not private.is_super_admin() then
    raise exception 'advance approval requires super_admin' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger advance_approval_guard before update on public.advances
  for each row execute function private.enforce_advance_approval();

create or replace function private.enforce_payroll_item_lock()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_status public.payroll_status;
begin
  select status into v_status from public.payroll_runs
  where id = coalesce(new.run_id, old.run_id);
  if v_status in ('approved', 'locked') and not private.is_super_admin() then
    raise exception 'payroll run is locked' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;

create trigger payroll_item_lock_guard before insert or update or delete on public.payroll_items
  for each row execute function private.enforce_payroll_item_lock();

-- ---- updated_at + audit -----------------------------------------------------
create trigger set_updated_at before update on public.leave_types
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.leaves
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.advances
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.payroll_runs
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.payroll_items
  for each row execute function private.set_updated_at();

create trigger audit_advances after insert or update or delete on public.advances
  for each row execute function private.audit_trigger();
create trigger audit_payroll_runs after insert or update or delete on public.payroll_runs
  for each row execute function private.audit_trigger();
create trigger audit_payroll_items after insert or update or delete on public.payroll_items
  for each row execute function private.audit_trigger();

-- ---- RLS (all org-scoped) --------------------------------------------------
alter table public.leave_types        enable row level security;
alter table public.leave_balances     enable row level security;
alter table public.leaves             enable row level security;
alter table public.advances           enable row level security;
alter table public.payroll_runs       enable row level security;
alter table public.payroll_items      enable row level security;
alter table public.advance_deductions enable row level security;

grant select, insert, update, delete on
  public.leave_types, public.leave_balances, public.leaves, public.advances,
  public.payroll_runs, public.payroll_items, public.advance_deductions
  to authenticated;

-- leave_types (super_admin config)
create policy "leavetype_select" on public.leave_types for select to authenticated
  using (org_id = private.current_org_id());
create policy "leavetype_insert" on public.leave_types for insert to authenticated
  with check (private.is_super_admin() and org_id = private.current_org_id());
create policy "leavetype_update" on public.leave_types for update to authenticated
  using (private.is_super_admin()) with check (private.is_super_admin());
create policy "leavetype_delete" on public.leave_types for delete to authenticated
  using (private.is_super_admin());

-- helper macro pattern for the org-scoped member-managed tables
create policy "leavebal_select" on public.leave_balances for select to authenticated
  using (org_id = private.current_org_id());
create policy "leavebal_write_ins" on public.leave_balances for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "leavebal_write_upd" on public.leave_balances for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "leavebal_delete" on public.leave_balances for delete to authenticated
  using (private.is_super_admin());

create policy "leaves_select" on public.leaves for select to authenticated
  using (org_id = private.current_org_id());
create policy "leaves_insert" on public.leaves for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "leaves_update" on public.leaves for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "leaves_delete" on public.leaves for delete to authenticated
  using (private.is_super_admin());

create policy "advances_select" on public.advances for select to authenticated
  using (org_id = private.current_org_id());
create policy "advances_insert" on public.advances for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "advances_update" on public.advances for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "advances_delete" on public.advances for delete to authenticated
  using (private.is_super_admin());

create policy "payrollrun_select" on public.payroll_runs for select to authenticated
  using (org_id = private.current_org_id());
create policy "payrollrun_insert" on public.payroll_runs for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "payrollrun_update" on public.payroll_runs for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "payrollrun_delete" on public.payroll_runs for delete to authenticated
  using (private.is_super_admin());

create policy "payrollitem_select" on public.payroll_items for select to authenticated
  using (org_id = private.current_org_id());
create policy "payrollitem_insert" on public.payroll_items for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "payrollitem_update" on public.payroll_items for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "payrollitem_delete" on public.payroll_items for delete to authenticated
  using (private.is_super_admin());

create policy "advdeduct_select" on public.advance_deductions for select to authenticated
  using (org_id = private.current_org_id());
create policy "advdeduct_insert" on public.advance_deductions for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "advdeduct_update" on public.advance_deductions for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "advdeduct_delete" on public.advance_deductions for delete to authenticated
  using (private.is_super_admin());
