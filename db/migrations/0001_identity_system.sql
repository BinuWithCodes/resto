-- ============================================================================
-- Migration 0001 — Identity & system foundation
-- Tables: organizations, locations, users, memberships, audit_logs,
--         system_metrics, notifications_log
-- Every table: RLS enabled + per-operation policies + indexes, in THIS file (§4.2).
-- RLS authority: security-definer helpers in the `private` schema reading
--   `memberships` (locked decision) — NOT the JWT. auth.uid() wrapped in (select ...).
-- Immutable once applied (§8): correct mistakes with a new migration.
-- ============================================================================

-- ---- Extensions -------------------------------------------------------------
create extension if not exists pgcrypto;      -- gen_random_uuid()

-- ---- Private schema for security-definer helpers (non-public, §4.2) ---------
create schema if not exists private;
revoke all on schema private from anon, authenticated;

-- ---- Enums ------------------------------------------------------------------
create type public.location_type as enum ('restaurant', 'hostel');
create type public.app_role      as enum ('super_admin', 'admin');

-- ---- updated_at helper ------------------------------------------------------
create or replace function private.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ============================================================================
-- TABLES
-- ============================================================================

-- organizations (single row in practice) ------------------------------------
create table public.organizations (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- locations ------------------------------------------------------------------
create table public.locations (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id) on delete restrict,
  type       public.location_type not null,
  name       text not null,
  address    text,
  phone      text,
  active     boolean not null default true,
  settings   jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_locations_org_id on public.locations(org_id);

-- users (mirror of auth.users) -----------------------------------------------
create table public.users (
  id         uuid primary key references auth.users(id) on delete cascade,
  org_id     uuid references public.organizations(id) on delete set null,
  email      text,
  full_name  text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_users_org_id on public.users(org_id);

-- memberships (user <-> location <-> role; NULL location_id = org-wide super_admin)
create table public.memberships (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  user_id     uuid not null references public.users(id)        on delete cascade,
  location_id uuid          references public.locations(id)     on delete cascade,
  role        public.app_role not null,
  created_at  timestamptz not null default now()
);
create index idx_memberships_user_id     on public.memberships(user_id);
create index idx_memberships_location_id on public.memberships(location_id);
create index idx_memberships_org_id      on public.memberships(org_id);
-- one row per (user, location); and only one org-wide row per user
create unique index uq_memberships_user_location
  on public.memberships(user_id, location_id) where location_id is not null;
create unique index uq_memberships_user_orgwide
  on public.memberships(user_id) where location_id is null;

-- audit_logs (INSERT-only; written by triggers) ------------------------------
create table public.audit_logs (
  id         bigint generated always as identity primary key,
  org_id     uuid,
  actor      uuid,                    -- auth.uid() or NULL for system
  action     text not null,          -- INSERT / UPDATE / DELETE
  table_name text not null,
  record_id  text,
  before     jsonb,
  after      jsonb,
  at         timestamptz not null default now()
);
create index idx_audit_logs_org_id on public.audit_logs(org_id);
create index idx_audit_logs_table_record on public.audit_logs(table_name, record_id);
create index idx_audit_logs_at on public.audit_logs(at);

-- system_metrics (free-tier usage tracking; written by cron/service_role) -----
create table public.system_metrics (
  id           bigint generated always as identity primary key,
  org_id       uuid references public.organizations(id) on delete cascade,
  metric_key   text not null,        -- e.g. 'db_size_bytes', 'rows_total'
  metric_value numeric not null,
  captured_at  timestamptz not null default now()
);
create index idx_system_metrics_org_captured on public.system_metrics(org_id, captured_at);

-- notifications_log (wa.me / dashboard alert log) ----------------------------
create table public.notifications_log (
  id          bigint generated always as identity primary key,
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
  channel     text not null,         -- 'wa.me' | 'dashboard'
  recipient   text,
  template    text,
  payload     jsonb not null default '{}'::jsonb,
  status      text not null default 'created',
  created_at  timestamptz not null default now()
);
create index idx_notifications_log_org_id on public.notifications_log(org_id);
create index idx_notifications_log_location_id on public.notifications_log(location_id);

-- ============================================================================
-- SECURITY-DEFINER HELPERS (private schema; bypass RLS to avoid recursion)
-- ============================================================================
create or replace function private.current_org_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select org_id from public.memberships
  where user_id = (select auth.uid()) limit 1
$$;

create or replace function private.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.memberships
    where user_id = (select auth.uid())
      and role = 'super_admin'
      and location_id is null
  )
$$;

create or replace function private.has_location_access(loc_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_super_admin()
      or exists (
        select 1 from public.memberships
        where user_id = (select auth.uid())
          and location_id = loc_id
      )
$$;

grant execute on function
  private.current_org_id(), private.is_super_admin(), private.has_location_access(uuid)
  to authenticated;

-- ============================================================================
-- AUTH MIRROR: auth.users -> public.users (single-org: default org_id)
-- ============================================================================
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.users (id, email, org_id)
  values (new.id, new.email, (select id from public.organizations limit 1))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ============================================================================
-- GENERIC AUDIT TRIGGER (attached here to sensitive config tables;
-- money/stock tables attach it in their own later migrations, §4.4)
-- ============================================================================
create or replace function private.audit_trigger()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_org uuid;
begin
  v_org := coalesce(
    (case when tg_op = 'DELETE' then (to_jsonb(old)->>'org_id') else (to_jsonb(new)->>'org_id') end)::uuid,
    private.current_org_id()
  );
  insert into public.audit_logs (org_id, actor, action, table_name, record_id, before, after)
  values (
    v_org,
    (select auth.uid()),
    tg_op,
    tg_table_name,
    coalesce((to_jsonb(new)->>'id'), (to_jsonb(old)->>'id')),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- ============================================================================
-- updated_at + audit triggers
-- ============================================================================
create trigger set_updated_at before update on public.organizations
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.locations
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.users
  for each row execute function private.set_updated_at();

create trigger audit_locations   after insert or update or delete on public.locations
  for each row execute function private.audit_trigger();
create trigger audit_memberships after insert or update or delete on public.memberships
  for each row execute function private.audit_trigger();

-- ============================================================================
-- ROW-LEVEL SECURITY
-- ============================================================================
alter table public.organizations    enable row level security;
alter table public.locations         enable row level security;
alter table public.users             enable row level security;
alter table public.memberships       enable row level security;
alter table public.audit_logs        enable row level security;
alter table public.system_metrics    enable row level security;
alter table public.notifications_log enable row level security;

-- Hard-revoke write grants where writes must go through triggers/service_role
revoke insert, update, delete on public.audit_logs     from anon, authenticated;
revoke insert, update, delete on public.system_metrics from anon, authenticated;

-- ---- organizations ----------------------------------------------------------
create policy "org_select_members" on public.organizations
  for select to authenticated
  using (id = private.current_org_id());
create policy "org_update_superadmin" on public.organizations
  for update to authenticated
  using (private.is_super_admin())
  with check (private.is_super_admin());

-- ---- locations --------------------------------------------------------------
create policy "loc_select_access" on public.locations
  for select to authenticated
  using (private.has_location_access(id));
create policy "loc_insert_superadmin" on public.locations
  for insert to authenticated
  with check (private.is_super_admin() and org_id = private.current_org_id());
create policy "loc_update_superadmin" on public.locations
  for update to authenticated
  using (private.is_super_admin())
  with check (private.is_super_admin());
create policy "loc_delete_superadmin" on public.locations
  for delete to authenticated
  using (private.is_super_admin());

-- ---- users ------------------------------------------------------------------
create policy "users_select_self_or_super" on public.users
  for select to authenticated
  using (id = (select auth.uid()) or private.is_super_admin());
create policy "users_update_self_or_super" on public.users
  for update to authenticated
  using (id = (select auth.uid()) or private.is_super_admin())
  with check (id = (select auth.uid()) or private.is_super_admin());

-- ---- memberships ------------------------------------------------------------
create policy "mem_select_self_or_super" on public.memberships
  for select to authenticated
  using (user_id = (select auth.uid()) or private.is_super_admin());
create policy "mem_insert_superadmin" on public.memberships
  for insert to authenticated
  with check (private.is_super_admin());
create policy "mem_update_superadmin" on public.memberships
  for update to authenticated
  using (private.is_super_admin())
  with check (private.is_super_admin());
create policy "mem_delete_superadmin" on public.memberships
  for delete to authenticated
  using (private.is_super_admin());

-- ---- audit_logs (SELECT super_admin only; no write policies -> writes only via
--      the SECURITY DEFINER audit trigger / service_role) ---------------------
create policy "audit_select_superadmin" on public.audit_logs
  for select to authenticated
  using (private.is_super_admin());

-- ---- system_metrics (SELECT super_admin only; writes via service_role) ------
create policy "metrics_select_superadmin" on public.system_metrics
  for select to authenticated
  using (private.is_super_admin());

-- ---- notifications_log ------------------------------------------------------
create policy "notif_select_scope" on public.notifications_log
  for select to authenticated
  using (private.is_super_admin()
         or (location_id is not null and private.has_location_access(location_id)));
create policy "notif_insert_scope" on public.notifications_log
  for insert to authenticated
  with check (org_id = private.current_org_id()
              and (private.is_super_admin()
                   or (location_id is not null and private.has_location_access(location_id))));
