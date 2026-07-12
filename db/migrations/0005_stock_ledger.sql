-- ============================================================================
-- Migration 0005 — Stock movements ledger + balances cache (Phase 1, §4.4)
-- ALL stock changes flow through the append-only stock_movements table. Current
-- stock = SUM(qty_delta) per (location, item), cached in stock_balances and
-- maintained by a trigger with a negative-stock guard. Movements are never
-- updated or deleted (append-only) — this is what makes shrinkage provable.
-- ============================================================================

create type public.stock_movement_type as enum (
  'purchase', 'purchase_return', 'consumption', 'waste',
  'transfer_out', 'transfer_in', 'internal_issue', 'adjustment'
);

-- ---- stock_movements (append-only ledger) ----------------------------------
create table public.stock_movements (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id) on delete cascade,
  location_id      uuid not null references public.locations(id) on delete restrict,
  item_id          uuid not null references public.stock_items(id) on delete restrict,
  movement_type    public.stock_movement_type not null,
  qty_delta        numeric(12, 3) not null,
  rate_paise       bigint check (rate_paise is null or rate_paise >= 0),
  ref_table        text,
  ref_id           uuid,
  shift_session_id uuid references public.shift_sessions(id) on delete set null,
  note             text,
  created_by       uuid references public.users(id),
  created_at       timestamptz not null default now()
);
create index idx_stock_movements_loc_item on public.stock_movements(location_id, item_id);
create index idx_stock_movements_item_id on public.stock_movements(item_id);
create index idx_stock_movements_org_id on public.stock_movements(org_id);
create index idx_stock_movements_session_id on public.stock_movements(shift_session_id);
create index idx_stock_movements_created_at on public.stock_movements(created_at);

-- ---- stock_balances (trigger-maintained cache) -----------------------------
create table public.stock_balances (
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete cascade,
  item_id     uuid not null references public.stock_items(id) on delete cascade,
  qty         numeric(12, 3) not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (location_id, item_id)
);
create index idx_stock_balances_org_id on public.stock_balances(org_id);
create index idx_stock_balances_item_id on public.stock_balances(item_id);

-- ---- balance maintenance + negative-stock guard ----------------------------
create or replace function private.apply_stock_movement()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_qty numeric(12, 3);
begin
  insert into public.stock_balances (org_id, location_id, item_id, qty)
  values (new.org_id, new.location_id, new.item_id, new.qty_delta)
  on conflict (location_id, item_id)
  do update set qty = public.stock_balances.qty + excluded.qty, updated_at = now()
  returning qty into v_qty;

  if v_qty < 0 then
    raise exception 'insufficient stock for item % at location %', new.item_id, new.location_id
      using errcode = '23514';
  end if;
  return new;
end $$;

create trigger apply_movement after insert on public.stock_movements
  for each row execute function private.apply_stock_movement();

-- ---- RLS -------------------------------------------------------------------
alter table public.stock_movements enable row level security;
alter table public.stock_balances  enable row level security;

-- movements: append-only for clients (select + insert; never update/delete)
grant select, insert on public.stock_movements to authenticated;
revoke update, delete on public.stock_movements from anon, authenticated;
-- balances: read-only for clients (written only by the SECURITY DEFINER trigger)
grant select on public.stock_balances to authenticated;
revoke insert, update, delete on public.stock_balances from anon, authenticated;

create policy "stockmov_select" on public.stock_movements
  for select to authenticated using (private.has_location_access(location_id));
create policy "stockmov_insert" on public.stock_movements
  for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());

create policy "stockbal_select" on public.stock_balances
  for select to authenticated using (private.has_location_access(location_id));
