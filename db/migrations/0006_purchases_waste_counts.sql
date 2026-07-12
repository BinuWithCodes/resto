-- ============================================================================
-- Migration 0006 — Purchases, supplier payments, waste, counts, templates
-- (Phase 1). All location-scoped (has_location_access) except supplier_payments
-- (org-scoped). These are the source tables; the transactional RPCs that post
-- their stock_movements arrive in 0007 (§4.4).
-- ============================================================================

create type public.purchase_payment_status as enum ('paid', 'credit');
create type public.waste_reason as enum (
  'expired', 'spoiled', 'overcooked', 'customer_return', 'damaged', 'other'
);
create type public.stock_count_status as enum ('draft', 'posted');

-- ---- purchases -------------------------------------------------------------
create table public.purchases (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id) on delete cascade,
  location_id      uuid not null references public.locations(id) on delete restrict,
  supplier_id      uuid references public.suppliers(id) on delete set null,
  purchase_date    date not null,
  payment_status   public.purchase_payment_status not null default 'paid',
  total_paise      bigint not null default 0 check (total_paise >= 0),
  shift_session_id uuid references public.shift_sessions(id) on delete set null,
  notes            text,
  created_by       uuid references public.users(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index idx_purchases_location_id on public.purchases(location_id);
create index idx_purchases_org_id on public.purchases(org_id);
create index idx_purchases_supplier_id on public.purchases(supplier_id);

create table public.purchase_items (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  location_id     uuid not null references public.locations(id) on delete restrict,
  purchase_id     uuid not null references public.purchases(id) on delete cascade,
  item_id         uuid not null references public.stock_items(id) on delete restrict,
  qty             numeric(12, 3) not null check (qty >= 0),
  rate_paise      bigint not null check (rate_paise >= 0),
  line_total_paise bigint not null check (line_total_paise >= 0),
  created_at      timestamptz not null default now()
);
create index idx_purchase_items_purchase_id on public.purchase_items(purchase_id);
create index idx_purchase_items_item_id on public.purchase_items(item_id);
create index idx_purchase_items_location_id on public.purchase_items(location_id);

-- ---- supplier_payments (org-scoped) ----------------------------------------
create table public.supplier_payments (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  supplier_id  uuid not null references public.suppliers(id) on delete restrict,
  amount_paise bigint not null check (amount_paise >= 0),
  paid_date    date not null,
  mode         public.income_mode,
  note         text,
  created_by   uuid references public.users(id),
  created_at   timestamptz not null default now()
);
create index idx_supplier_payments_supplier_id on public.supplier_payments(supplier_id);
create index idx_supplier_payments_org_id on public.supplier_payments(org_id);

-- ---- waste_logs ------------------------------------------------------------
create table public.waste_logs (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id) on delete cascade,
  location_id      uuid not null references public.locations(id) on delete restrict,
  item_id          uuid not null references public.stock_items(id) on delete restrict,
  qty              numeric(12, 3) not null check (qty >= 0),
  reason_code      public.waste_reason not null,
  shift_session_id uuid references public.shift_sessions(id) on delete set null,
  cost_paise       bigint not null default 0 check (cost_paise >= 0),
  note             text,
  created_by       uuid references public.users(id),
  created_at       timestamptz not null default now()
);
create index idx_waste_logs_location_id on public.waste_logs(location_id);
create index idx_waste_logs_item_id on public.waste_logs(item_id);
create index idx_waste_logs_org_id on public.waste_logs(org_id);

-- ---- stock_counts ----------------------------------------------------------
create table public.stock_counts (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  count_date  date not null,
  status      public.stock_count_status not null default 'draft',
  notes       text,
  created_by  uuid references public.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_stock_counts_location_id on public.stock_counts(location_id);
create index idx_stock_counts_org_id on public.stock_counts(org_id);

create table public.stock_count_items (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null references public.organizations(id) on delete cascade,
  location_id          uuid not null references public.locations(id) on delete restrict,
  count_id             uuid not null references public.stock_counts(id) on delete cascade,
  item_id              uuid not null references public.stock_items(id) on delete restrict,
  system_qty           numeric(12, 3) not null default 0,
  counted_qty          numeric(12, 3) not null default 0,
  variance_qty         numeric(12, 3) not null default 0,
  variance_value_paise bigint not null default 0,
  reason               text
);
create index idx_stock_count_items_count_id on public.stock_count_items(count_id);
create index idx_stock_count_items_item_id on public.stock_count_items(item_id);
create index idx_stock_count_items_location_id on public.stock_count_items(location_id);

-- ---- consumption_templates -------------------------------------------------
create table public.consumption_templates (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  location_id  uuid not null references public.locations(id) on delete restrict,
  shift_def_id uuid references public.shift_definitions(id) on delete set null,
  name         text not null,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index idx_consumption_templates_location_id on public.consumption_templates(location_id);
create index idx_consumption_templates_org_id on public.consumption_templates(org_id);

create table public.consumption_template_items (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  template_id uuid not null references public.consumption_templates(id) on delete cascade,
  item_id     uuid not null references public.stock_items(id) on delete restrict,
  default_qty numeric(12, 3) not null default 0 check (default_qty >= 0)
);
create index idx_consumption_template_items_template_id on public.consumption_template_items(template_id);

-- ---- triggers --------------------------------------------------------------
create trigger set_updated_at before update on public.purchases
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.stock_counts
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.consumption_templates
  for each row execute function private.set_updated_at();

create trigger audit_purchases after insert or update or delete on public.purchases
  for each row execute function private.audit_trigger();
create trigger audit_supplier_payments after insert or update or delete on public.supplier_payments
  for each row execute function private.audit_trigger();
create trigger audit_waste_logs after insert or update or delete on public.waste_logs
  for each row execute function private.audit_trigger();

-- ---- RLS -------------------------------------------------------------------
alter table public.purchases                  enable row level security;
alter table public.purchase_items             enable row level security;
alter table public.supplier_payments          enable row level security;
alter table public.waste_logs                 enable row level security;
alter table public.stock_counts               enable row level security;
alter table public.stock_count_items          enable row level security;
alter table public.consumption_templates      enable row level security;
alter table public.consumption_template_items enable row level security;

grant select, insert, update, delete on
  public.purchases, public.purchase_items, public.supplier_payments,
  public.waste_logs, public.stock_counts, public.stock_count_items,
  public.consumption_templates, public.consumption_template_items
  to authenticated;

-- Location-scoped tables: read/insert/update for members with access; delete
-- super_admin only (admins never delete records, §1.1).
-- purchases
create policy "purchases_select" on public.purchases for select to authenticated
  using (private.has_location_access(location_id));
create policy "purchases_insert" on public.purchases for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "purchases_update" on public.purchases for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "purchases_delete" on public.purchases for delete to authenticated
  using (private.is_super_admin());

-- purchase_items
create policy "purchaseitems_select" on public.purchase_items for select to authenticated
  using (private.has_location_access(location_id));
create policy "purchaseitems_insert" on public.purchase_items for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "purchaseitems_update" on public.purchase_items for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "purchaseitems_delete" on public.purchase_items for delete to authenticated
  using (private.is_super_admin());

-- supplier_payments (org-scoped)
create policy "supplierpay_select" on public.supplier_payments for select to authenticated
  using (org_id = private.current_org_id());
create policy "supplierpay_insert" on public.supplier_payments for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "supplierpay_update" on public.supplier_payments for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "supplierpay_delete" on public.supplier_payments for delete to authenticated
  using (private.is_super_admin());

-- waste_logs
create policy "waste_select" on public.waste_logs for select to authenticated
  using (private.has_location_access(location_id));
create policy "waste_insert" on public.waste_logs for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "waste_update" on public.waste_logs for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "waste_delete" on public.waste_logs for delete to authenticated
  using (private.is_super_admin());

-- stock_counts
create policy "counts_select" on public.stock_counts for select to authenticated
  using (private.has_location_access(location_id));
create policy "counts_insert" on public.stock_counts for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "counts_update" on public.stock_counts for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "counts_delete" on public.stock_counts for delete to authenticated
  using (private.is_super_admin());

-- stock_count_items
create policy "countitems_select" on public.stock_count_items for select to authenticated
  using (private.has_location_access(location_id));
create policy "countitems_insert" on public.stock_count_items for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "countitems_update" on public.stock_count_items for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "countitems_delete" on public.stock_count_items for delete to authenticated
  using (private.is_super_admin());

-- consumption_templates
create policy "ctmpl_select" on public.consumption_templates for select to authenticated
  using (private.has_location_access(location_id));
create policy "ctmpl_insert" on public.consumption_templates for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "ctmpl_update" on public.consumption_templates for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "ctmpl_delete" on public.consumption_templates for delete to authenticated
  using (private.is_super_admin());

-- consumption_template_items (org-scoped; parent carries the location)
create policy "ctmplitems_select" on public.consumption_template_items for select to authenticated
  using (org_id = private.current_org_id());
create policy "ctmplitems_insert" on public.consumption_template_items for insert to authenticated
  with check (org_id = private.current_org_id());
create policy "ctmplitems_update" on public.consumption_template_items for update to authenticated
  using (org_id = private.current_org_id()) with check (org_id = private.current_org_id());
create policy "ctmplitems_delete" on public.consumption_template_items for delete to authenticated
  using (private.is_super_admin());
