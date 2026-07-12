-- ============================================================================
-- Migration 0010 — Staff core (Phase 3): employees, roster_entries, attendance
-- Employees are org-level (shared across locations). Roster + attendance are
-- location-scoped (an admin marks only their location's staff, §6). Attendance
-- locks after its payroll run; locked rows reject edits by non-super_admin (§4.4).
-- ============================================================================

create type public.employee_status  as enum ('active', 'on_leave', 'left');
create type public.roster_shift     as enum ('breakfast', 'lunch', 'dinner', 'full', 'night');
create type public.attendance_status as enum ('present', 'absent', 'half', 'leave', 'weekoff');

-- ---- employees (org-level) -------------------------------------------------
create table public.employees (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null references public.organizations(id) on delete cascade,
  name                 text not null,
  phone                text,
  dob                  date,
  gender               text,
  present_address      text,
  permanent_address    text,
  emergency_contact    jsonb not null default '{}'::jsonb,
  designation          text,
  monthly_salary_paise bigint not null default 0 check (monthly_salary_paise >= 0),
  bank_upi_reference   text,
  status               public.employee_status not null default 'active',
  join_date            date,
  exit_date            date,
  exit_reason          text,
  notes                text,
  created_by           uuid references public.users(id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index idx_employees_org_id on public.employees(org_id);
create index idx_employees_status on public.employees(status);

-- ---- roster_entries --------------------------------------------------------
create table public.roster_entries (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete cascade,
  duty_date   date not null,
  shift       public.roster_shift not null,
  created_by  uuid references public.users(id),
  created_at  timestamptz not null default now(),
  unique (employee_id, duty_date, shift)
);
create index idx_roster_entries_location_id on public.roster_entries(location_id);
create index idx_roster_entries_employee_id on public.roster_entries(employee_id);
create index idx_roster_entries_duty_date on public.roster_entries(duty_date);

-- ---- attendance ------------------------------------------------------------
create table public.attendance (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  location_id  uuid not null references public.locations(id) on delete restrict,
  employee_id  uuid not null references public.employees(id) on delete cascade,
  att_date     date not null,
  status       public.attendance_status not null,
  late_minutes integer not null default 0 check (late_minutes >= 0),
  ot_hours     numeric(5, 2) not null default 0 check (ot_hours >= 0),
  locked       boolean not null default false,
  created_by   uuid references public.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (employee_id, att_date)
);
create index idx_attendance_location_id on public.attendance(location_id);
create index idx_attendance_employee_id on public.attendance(employee_id);
create index idx_attendance_att_date on public.attendance(att_date);

-- ---- Locked attendance rejects edits by non-super_admin (§4.4) -------------
create or replace function private.enforce_attendance_lock()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.locked and not private.is_super_admin() then
    raise exception 'attendance is locked after payroll' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger attendance_lock_guard before update on public.attendance
  for each row execute function private.enforce_attendance_lock();

-- ---- triggers --------------------------------------------------------------
create trigger set_updated_at before update on public.employees
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.attendance
  for each row execute function private.set_updated_at();

create trigger audit_employees after insert or update or delete on public.employees
  for each row execute function private.audit_trigger();
create trigger audit_attendance after insert or update or delete on public.attendance
  for each row execute function private.audit_trigger();

-- ---- RLS -------------------------------------------------------------------
alter table public.employees      enable row level security;
alter table public.roster_entries enable row level security;
alter table public.attendance     enable row level security;

grant select, insert, update, delete on
  public.employees, public.roster_entries, public.attendance
  to authenticated;

-- employees (org-level): members read/insert/update; super_admin deletes
create policy "employees_select" on public.employees for select to authenticated
  using (org_id = private.current_org_id());
create policy "employees_insert" on public.employees for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "employees_update" on public.employees for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "employees_delete" on public.employees for delete to authenticated
  using (private.is_super_admin());

-- roster_entries (location-scoped)
create policy "roster_select" on public.roster_entries for select to authenticated
  using (private.has_location_access(location_id));
create policy "roster_insert" on public.roster_entries for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "roster_update" on public.roster_entries for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "roster_delete" on public.roster_entries for delete to authenticated
  using (private.has_location_access(location_id));

-- attendance (location-scoped; lock enforced by trigger)
create policy "attendance_select" on public.attendance for select to authenticated
  using (private.has_location_access(location_id));
create policy "attendance_insert" on public.attendance for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "attendance_update" on public.attendance for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "attendance_delete" on public.attendance for delete to authenticated
  using (private.is_super_admin());
