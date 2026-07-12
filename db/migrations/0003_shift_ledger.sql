-- ============================================================================
-- Migration 0003 — Restaurant shift ledger (Phase 1)
-- shift_definitions, shift_sessions, shift_income_entries, expense_categories,
-- shift_expense_entries. Every table: RLS + policies + indexes here (§4.2).
-- Money is bigint paise with CHECK (>= 0). Locking (§4.4): a locked session
-- rejects writes for non-super_admin, enforced in RLS (session) and a trigger
-- (entries). org_id + location_id denormalised onto entries for simple, fast
-- policies (§4.1).
-- ============================================================================

create type public.shift_status  as enum ('open', 'closed', 'locked');
create type public.income_source as enum ('dine_in', 'parcel', 'bulk', 'catering', 'other');
create type public.income_mode   as enum ('cash', 'upi', 'card');
create type public.expense_mode  as enum ('cash', 'upi', 'credit');

-- ---- shift_definitions (org-level config) ----------------------------------
create table public.shift_definitions (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id) on delete cascade,
  name       text not null,
  start_time time not null,
  end_time   time not null,
  sort_order integer not null default 0,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_shift_definitions_org_id on public.shift_definitions(org_id);

-- ---- shift_sessions --------------------------------------------------------
create table public.shift_sessions (
  id                          uuid primary key default gen_random_uuid(),
  org_id                      uuid not null references public.organizations(id) on delete cascade,
  location_id                 uuid not null references public.locations(id) on delete restrict,
  shift_def_id                uuid not null references public.shift_definitions(id) on delete restrict,
  business_date               date not null,
  status                      public.shift_status not null default 'open',
  opening_cash_paise          bigint not null default 0 check (opening_cash_paise >= 0),
  expected_closing_cash_paise bigint,
  actual_closing_cash_paise   bigint check (actual_closing_cash_paise is null or actual_closing_cash_paise >= 0),
  variance_paise              bigint,
  variance_reason             text,
  handover_note               text,
  opened_by                   uuid references public.users(id),
  closed_by                   uuid references public.users(id),
  closed_at                   timestamptz,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  unique (location_id, shift_def_id, business_date)
);
create index idx_shift_sessions_location_id on public.shift_sessions(location_id);
create index idx_shift_sessions_org_id on public.shift_sessions(org_id);
create index idx_shift_sessions_business_date on public.shift_sessions(business_date);
create index idx_shift_sessions_status on public.shift_sessions(status);

-- ---- shift_income_entries --------------------------------------------------
create table public.shift_income_entries (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references public.organizations(id) on delete cascade,
  location_id    uuid not null references public.locations(id) on delete restrict,
  session_id     uuid not null references public.shift_sessions(id) on delete cascade,
  source         public.income_source not null,
  mode           public.income_mode not null,
  amount_paise   bigint not null check (amount_paise >= 0),
  customer_count integer check (customer_count is null or customer_count >= 0),
  note           text,
  created_by     uuid references public.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index idx_shift_income_session_id on public.shift_income_entries(session_id);
create index idx_shift_income_location_id on public.shift_income_entries(location_id);
create index idx_shift_income_org_id on public.shift_income_entries(org_id);

-- ---- expense_categories (org-level config) ---------------------------------
create table public.expense_categories (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id) on delete cascade,
  name       text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name)
);
create index idx_expense_categories_org_id on public.expense_categories(org_id);

-- ---- shift_expense_entries -------------------------------------------------
-- supplier_id has no FK yet; the suppliers table (and this FK) arrive in the
-- stock migration (0004).
create table public.shift_expense_entries (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  location_id  uuid not null references public.locations(id) on delete restrict,
  session_id   uuid not null references public.shift_sessions(id) on delete cascade,
  category_id  uuid references public.expense_categories(id) on delete set null,
  description  text,
  amount_paise bigint not null check (amount_paise >= 0),
  mode         public.expense_mode not null,
  supplier_id  uuid,
  settled      boolean not null default false,
  settled_at   timestamptz,
  created_by   uuid references public.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index idx_shift_expense_session_id on public.shift_expense_entries(session_id);
create index idx_shift_expense_location_id on public.shift_expense_entries(location_id);
create index idx_shift_expense_org_id on public.shift_expense_entries(org_id);
create index idx_shift_expense_supplier_id on public.shift_expense_entries(supplier_id);

-- ============================================================================
-- Lock enforcement: writes to entries of a locked session are blocked for
-- non-super_admin (§4.4). SECURITY DEFINER so it can read the session status.
-- ============================================================================
create or replace function private.enforce_shift_not_locked()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_status public.shift_status;
begin
  select status into v_status
  from public.shift_sessions
  where id = coalesce(new.session_id, old.session_id);
  if v_status = 'locked' and not private.is_super_admin() then
    raise exception 'shift session is locked' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;

-- ============================================================================
-- updated_at + audit + lock triggers
-- ============================================================================
create trigger set_updated_at before update on public.shift_definitions
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.shift_sessions
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.shift_income_entries
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.expense_categories
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.shift_expense_entries
  for each row execute function private.set_updated_at();

create trigger audit_shift_sessions after insert or update or delete on public.shift_sessions
  for each row execute function private.audit_trigger();
create trigger audit_shift_income after insert or update or delete on public.shift_income_entries
  for each row execute function private.audit_trigger();
create trigger audit_shift_expense after insert or update or delete on public.shift_expense_entries
  for each row execute function private.audit_trigger();

create trigger lock_guard_income before insert or update or delete on public.shift_income_entries
  for each row execute function private.enforce_shift_not_locked();
create trigger lock_guard_expense before insert or update or delete on public.shift_expense_entries
  for each row execute function private.enforce_shift_not_locked();

-- ============================================================================
-- RLS
-- ============================================================================
alter table public.shift_definitions    enable row level security;
alter table public.shift_sessions        enable row level security;
alter table public.shift_income_entries  enable row level security;
alter table public.expense_categories    enable row level security;
alter table public.shift_expense_entries enable row level security;

grant select, insert, update, delete on
  public.shift_definitions, public.shift_sessions, public.shift_income_entries,
  public.expense_categories, public.shift_expense_entries
  to authenticated;

-- shift_definitions — org config: read for members, write super_admin only
create policy "shiftdef_select" on public.shift_definitions
  for select to authenticated using (org_id = private.current_org_id());
create policy "shiftdef_insert" on public.shift_definitions
  for insert to authenticated with check (private.is_super_admin() and org_id = private.current_org_id());
create policy "shiftdef_update" on public.shift_definitions
  for update to authenticated using (private.is_super_admin()) with check (private.is_super_admin());
create policy "shiftdef_delete" on public.shift_definitions
  for delete to authenticated using (private.is_super_admin());

-- expense_categories — org config
create policy "expcat_select" on public.expense_categories
  for select to authenticated using (org_id = private.current_org_id());
create policy "expcat_insert" on public.expense_categories
  for insert to authenticated with check (private.is_super_admin() and org_id = private.current_org_id());
create policy "expcat_update" on public.expense_categories
  for update to authenticated using (private.is_super_admin()) with check (private.is_super_admin());
create policy "expcat_delete" on public.expense_categories
  for delete to authenticated using (private.is_super_admin());

-- shift_sessions — location-scoped; locked rows reject writes for non-super_admin
create policy "shiftses_select" on public.shift_sessions
  for select to authenticated using (private.has_location_access(location_id));
create policy "shiftses_insert" on public.shift_sessions
  for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "shiftses_update" on public.shift_sessions
  for update to authenticated
  using (private.has_location_access(location_id) and (status <> 'locked' or private.is_super_admin()))
  with check (private.has_location_access(location_id));
create policy "shiftses_delete" on public.shift_sessions
  for delete to authenticated using (private.is_super_admin());

-- shift_income_entries — location-scoped (lock enforced by trigger)
create policy "shiftinc_select" on public.shift_income_entries
  for select to authenticated using (private.has_location_access(location_id));
create policy "shiftinc_insert" on public.shift_income_entries
  for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "shiftinc_update" on public.shift_income_entries
  for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "shiftinc_delete" on public.shift_income_entries
  for delete to authenticated using (private.has_location_access(location_id));

-- shift_expense_entries — location-scoped (lock enforced by trigger)
create policy "shiftexp_select" on public.shift_expense_entries
  for select to authenticated using (private.has_location_access(location_id));
create policy "shiftexp_insert" on public.shift_expense_entries
  for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "shiftexp_update" on public.shift_expense_entries
  for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "shiftexp_delete" on public.shift_expense_entries
  for delete to authenticated using (private.has_location_access(location_id));
