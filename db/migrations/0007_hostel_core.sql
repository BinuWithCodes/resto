-- ============================================================================
-- Migration 0007 — Hostel core (Phase 2): rooms, beds, tenants, bed_assignments
-- Location-scoped via has_location_access. Text-only KYC (§1.2): NO photo/file
-- columns. Aadhaar rule (§7): tenants.aadhaar_last4 holds EXACTLY 4 digits,
-- enforced by CHECK here and by Zod at the edge. Full Aadhaar never stored.
-- ============================================================================

create type public.bed_status    as enum ('vacant', 'occupied', 'notice', 'maintenance', 'reserved');
create type public.tenant_status as enum ('active', 'notice', 'vacated', 'blacklisted');

-- ---- rooms -----------------------------------------------------------------
create table public.rooms (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  number      text not null,
  floor       text,
  room_type   text,
  capacity    integer check (capacity is null or capacity >= 0),
  amenities   jsonb not null default '{}'::jsonb,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (location_id, number)
);
create index idx_rooms_location_id on public.rooms(location_id);
create index idx_rooms_org_id on public.rooms(org_id);

-- ---- beds ------------------------------------------------------------------
create table public.beds (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  room_id     uuid not null references public.rooms(id) on delete cascade,
  label       text not null,
  status      public.bed_status not null default 'vacant',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (room_id, label)
);
create index idx_beds_room_id on public.beds(room_id);
create index idx_beds_location_id on public.beds(location_id);
create index idx_beds_org_id on public.beds(org_id);

-- ---- tenants (text-only KYC) -----------------------------------------------
create table public.tenants (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations(id) on delete cascade,
  location_id        uuid not null references public.locations(id) on delete restrict,
  name               text not null,
  phone              text,
  alt_phone          text,
  email              text,
  dob                date,
  gender             text,
  present_address    text,
  permanent_address  text,
  emergency_contact  jsonb not null default '{}'::jsonb,
  occupation         text,
  -- ONLY the last 4 digits, ever (§7). Reject anything but 4 digits.
  aadhaar_last4      text check (aadhaar_last4 is null or aadhaar_last4 ~ '^[0-9]{4}$'),
  consent_at         timestamptz,
  join_date          date,
  rent_paise         bigint not null default 0 check (rent_paise >= 0),
  deposit_paise      bigint not null default 0 check (deposit_paise >= 0),
  notice_days        integer not null default 30 check (notice_days >= 0),
  status             public.tenant_status not null default 'active',
  notes              text,
  created_by         uuid references public.users(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index idx_tenants_location_id on public.tenants(location_id);
create index idx_tenants_org_id on public.tenants(org_id);
create index idx_tenants_status on public.tenants(status);

-- ---- bed_assignments (history preserved) -----------------------------------
create table public.bed_assignments (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  bed_id      uuid not null references public.beds(id) on delete restrict,
  from_date   date not null,
  to_date     date,
  created_by  uuid references public.users(id),
  created_at  timestamptz not null default now()
);
create index idx_bed_assignments_tenant_id on public.bed_assignments(tenant_id);
create index idx_bed_assignments_bed_id on public.bed_assignments(bed_id);
create index idx_bed_assignments_location_id on public.bed_assignments(location_id);

-- ---- triggers --------------------------------------------------------------
create trigger set_updated_at before update on public.rooms
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.beds
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.tenants
  for each row execute function private.set_updated_at();

create trigger audit_tenants after insert or update or delete on public.tenants
  for each row execute function private.audit_trigger();
create trigger audit_bed_assignments after insert or update or delete on public.bed_assignments
  for each row execute function private.audit_trigger();

-- ---- RLS -------------------------------------------------------------------
alter table public.rooms           enable row level security;
alter table public.beds            enable row level security;
alter table public.tenants         enable row level security;
alter table public.bed_assignments enable row level security;

grant select, insert, update, delete on
  public.rooms, public.beds, public.tenants, public.bed_assignments
  to authenticated;

-- rooms
create policy "rooms_select" on public.rooms for select to authenticated
  using (private.has_location_access(location_id));
create policy "rooms_insert" on public.rooms for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "rooms_update" on public.rooms for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "rooms_delete" on public.rooms for delete to authenticated
  using (private.is_super_admin());

-- beds
create policy "beds_select" on public.beds for select to authenticated
  using (private.has_location_access(location_id));
create policy "beds_insert" on public.beds for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "beds_update" on public.beds for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "beds_delete" on public.beds for delete to authenticated
  using (private.is_super_admin());

-- tenants
create policy "tenants_select" on public.tenants for select to authenticated
  using (private.has_location_access(location_id));
create policy "tenants_insert" on public.tenants for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "tenants_update" on public.tenants for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "tenants_delete" on public.tenants for delete to authenticated
  using (private.is_super_admin());

-- bed_assignments
create policy "bedassign_select" on public.bed_assignments for select to authenticated
  using (private.has_location_access(location_id));
create policy "bedassign_insert" on public.bed_assignments for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "bedassign_update" on public.bed_assignments for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "bedassign_delete" on public.bed_assignments for delete to authenticated
  using (private.is_super_admin());
