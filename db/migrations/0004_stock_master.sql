-- ============================================================================
-- Migration 0004 — Stock master + suppliers (Phase 1)
-- stock_categories, stock_items, suppliers. Org-level master data (no
-- location_id): read by org members, insert/update by any member (daily
-- purchasing work), delete super_admin only (admins never delete). Also adds
-- the deferred supplier FK to shift_expense_entries.
-- ============================================================================

-- ---- stock_categories ------------------------------------------------------
create table public.stock_categories (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id) on delete cascade,
  name       text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, name)
);
create index idx_stock_categories_org_id on public.stock_categories(org_id);

-- ---- suppliers -------------------------------------------------------------
create table public.suppliers (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations(id) on delete cascade,
  name       text not null,
  phone      text,
  category   text,
  address    text,
  notes      text,
  rating     smallint check (rating is null or rating between 1 and 5),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_suppliers_org_id on public.suppliers(org_id);

-- ---- stock_items -----------------------------------------------------------
create table public.stock_items (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null references public.organizations(id) on delete cascade,
  category_id          uuid references public.stock_categories(id) on delete set null,
  name                 text not null,
  base_unit            text not null,
  purchase_unit        text not null,
  conversion_factor    numeric(12, 4) not null default 1 check (conversion_factor > 0),
  sku                  text,
  perishable           boolean not null default false,
  shelf_life_days      integer check (shelf_life_days is null or shelf_life_days >= 0),
  reorder_level        numeric(12, 3) not null default 0 check (reorder_level >= 0),
  reorder_qty          numeric(12, 3) not null default 0 check (reorder_qty >= 0),
  standard_rate_paise  bigint not null default 0 check (standard_rate_paise >= 0),
  preferred_supplier_id uuid references public.suppliers(id) on delete set null,
  active               boolean not null default true,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index idx_stock_items_org_id on public.stock_items(org_id);
create index idx_stock_items_category_id on public.stock_items(category_id);
create index idx_stock_items_preferred_supplier_id on public.stock_items(preferred_supplier_id);

-- deferred FK from 0003
alter table public.shift_expense_entries
  add constraint fk_shift_expense_supplier
  foreign key (supplier_id) references public.suppliers(id) on delete set null;

-- ---- triggers --------------------------------------------------------------
create trigger set_updated_at before update on public.stock_categories
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.suppliers
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.stock_items
  for each row execute function private.set_updated_at();

create trigger audit_suppliers after insert or update or delete on public.suppliers
  for each row execute function private.audit_trigger();
create trigger audit_stock_items after insert or update or delete on public.stock_items
  for each row execute function private.audit_trigger();

-- ---- RLS -------------------------------------------------------------------
alter table public.stock_categories enable row level security;
alter table public.suppliers        enable row level security;
alter table public.stock_items      enable row level security;

grant select, insert, update, delete on
  public.stock_categories, public.suppliers, public.stock_items
  to authenticated;

-- Shared org master: members read + insert + update; only super_admin deletes.
create policy "stockcat_select" on public.stock_categories
  for select to authenticated using (org_id = private.current_org_id());
create policy "stockcat_insert" on public.stock_categories
  for insert to authenticated with check (org_id = private.current_org_id());
create policy "stockcat_update" on public.stock_categories
  for update to authenticated using (org_id = private.current_org_id())
  with check (org_id = private.current_org_id());
create policy "stockcat_delete" on public.stock_categories
  for delete to authenticated using (private.is_super_admin());

create policy "suppliers_select" on public.suppliers
  for select to authenticated using (org_id = private.current_org_id());
create policy "suppliers_insert" on public.suppliers
  for insert to authenticated with check (org_id = private.current_org_id());
create policy "suppliers_update" on public.suppliers
  for update to authenticated using (org_id = private.current_org_id())
  with check (org_id = private.current_org_id());
create policy "suppliers_delete" on public.suppliers
  for delete to authenticated using (private.is_super_admin());

create policy "stockitems_select" on public.stock_items
  for select to authenticated using (org_id = private.current_org_id());
create policy "stockitems_insert" on public.stock_items
  for insert to authenticated with check (org_id = private.current_org_id());
create policy "stockitems_update" on public.stock_items
  for update to authenticated using (org_id = private.current_org_id())
  with check (org_id = private.current_org_id());
create policy "stockitems_delete" on public.stock_items
  for delete to authenticated using (private.is_super_admin());
