-- ============================================================================
-- Migration 0009 — Utilities + meal plans (Phase 2)
-- utility_bills + utility_splits (feed rent invoices); meal_plans (org config)
-- + meal_subscriptions + meal_skips (feed restaurant headcount). Location-scoped
-- except meal_plans (org config). Money in paise; readings numeric(12,3).
-- ============================================================================

create type public.utility_type as enum ('electricity', 'water', 'gas');
create type public.utility_split_method as enum (
  'equal_per_bed', 'by_occupancy_days', 'by_room', 'fixed_per_bed'
);
create type public.meal_type as enum ('breakfast', 'lunch', 'dinner');

-- ---- utility_bills ---------------------------------------------------------
create table public.utility_bills (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  location_id  uuid not null references public.locations(id) on delete restrict,
  type         public.utility_type not null,
  period       text not null,
  total_paise  bigint not null default 0 check (total_paise >= 0),
  prev_reading numeric(12, 3),
  curr_reading numeric(12, 3),
  split_method public.utility_split_method not null default 'equal_per_bed',
  created_by   uuid references public.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index idx_utility_bills_location_id on public.utility_bills(location_id);
create index idx_utility_bills_org_id on public.utility_bills(org_id);

create table public.utility_splits (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  bill_id     uuid not null references public.utility_bills(id) on delete cascade,
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  share_paise bigint not null default 0 check (share_paise >= 0),
  created_at  timestamptz not null default now()
);
create index idx_utility_splits_bill_id on public.utility_splits(bill_id);
create index idx_utility_splits_tenant_id on public.utility_splits(tenant_id);
create index idx_utility_splits_location_id on public.utility_splits(location_id);

-- ---- meal_plans (org config) -----------------------------------------------
create table public.meal_plans (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null references public.organizations(id) on delete cascade,
  name                text not null,
  meals_included      jsonb not null default '[]'::jsonb,   -- e.g. ["breakfast","dinner"]
  monthly_price_paise bigint not null default 0 check (monthly_price_paise >= 0),
  active              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index idx_meal_plans_org_id on public.meal_plans(org_id);

-- ---- meal_subscriptions ----------------------------------------------------
create table public.meal_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  plan_id     uuid not null references public.meal_plans(id) on delete restrict,
  from_date   date not null,
  to_date     date,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_meal_subs_tenant_id on public.meal_subscriptions(tenant_id);
create index idx_meal_subs_location_id on public.meal_subscriptions(location_id);
create index idx_meal_subs_plan_id on public.meal_subscriptions(plan_id);

-- ---- meal_skips ------------------------------------------------------------
create table public.meal_skips (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  skip_date   date not null,
  meal        public.meal_type not null,
  created_by  uuid references public.users(id),
  created_at  timestamptz not null default now(),
  unique (tenant_id, skip_date, meal)
);
create index idx_meal_skips_tenant_id on public.meal_skips(tenant_id);
create index idx_meal_skips_location_id on public.meal_skips(location_id);
create index idx_meal_skips_date on public.meal_skips(skip_date);

-- ---- triggers --------------------------------------------------------------
create trigger set_updated_at before update on public.utility_bills
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.meal_plans
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.meal_subscriptions
  for each row execute function private.set_updated_at();

create trigger audit_utility_bills after insert or update or delete on public.utility_bills
  for each row execute function private.audit_trigger();

-- ---- RLS -------------------------------------------------------------------
alter table public.utility_bills       enable row level security;
alter table public.utility_splits      enable row level security;
alter table public.meal_plans          enable row level security;
alter table public.meal_subscriptions  enable row level security;
alter table public.meal_skips          enable row level security;

grant select, insert, update, delete on
  public.utility_bills, public.utility_splits, public.meal_plans,
  public.meal_subscriptions, public.meal_skips
  to authenticated;

-- utility_bills
create policy "utilbill_select" on public.utility_bills for select to authenticated
  using (private.has_location_access(location_id));
create policy "utilbill_insert" on public.utility_bills for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "utilbill_update" on public.utility_bills for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "utilbill_delete" on public.utility_bills for delete to authenticated
  using (private.is_super_admin());

-- utility_splits
create policy "utilsplit_select" on public.utility_splits for select to authenticated
  using (private.has_location_access(location_id));
create policy "utilsplit_insert" on public.utility_splits for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "utilsplit_update" on public.utility_splits for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "utilsplit_delete" on public.utility_splits for delete to authenticated
  using (private.is_super_admin());

-- meal_plans (org config)
create policy "mealplan_select" on public.meal_plans for select to authenticated
  using (org_id = private.current_org_id());
create policy "mealplan_insert" on public.meal_plans for insert to authenticated
  with check (private.is_super_admin() and org_id = private.current_org_id());
create policy "mealplan_update" on public.meal_plans for update to authenticated
  using (private.is_super_admin()) with check (private.is_super_admin());
create policy "mealplan_delete" on public.meal_plans for delete to authenticated
  using (private.is_super_admin());

-- meal_subscriptions
create policy "mealsub_select" on public.meal_subscriptions for select to authenticated
  using (private.has_location_access(location_id));
create policy "mealsub_insert" on public.meal_subscriptions for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "mealsub_update" on public.meal_subscriptions for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "mealsub_delete" on public.meal_subscriptions for delete to authenticated
  using (private.is_super_admin());

-- meal_skips
create policy "mealskip_select" on public.meal_skips for select to authenticated
  using (private.has_location_access(location_id));
create policy "mealskip_insert" on public.meal_skips for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "mealskip_update" on public.meal_skips for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "mealskip_delete" on public.meal_skips for delete to authenticated
  using (private.is_super_admin());
