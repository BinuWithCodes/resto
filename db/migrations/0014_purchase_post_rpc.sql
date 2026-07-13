-- ============================================================================
-- Migration 0014 — Purchase posting as a transactional RPC (§4.4) + idempotency
--
-- One Postgres function writes the purchase header, its line items, and the
-- matching append-only stock_movements in a single transaction. SECURITY
-- INVOKER so the caller's RLS applies to every statement — an admin can only
-- post purchases at their own locations, and only for their own org's items.
-- org_id is read from the target location row (visible only via RLS), which
-- both derives the org and enforces location access; the function never calls
-- the `private` helpers directly (authenticated lacks USAGE on that schema —
-- those helpers are reachable only through RLS policy evaluation).
--
-- Unit convention (matches lib/stock.ts + stock_items.standard_rate_paise):
--   * qty is in BASE units (same as stock_movements.qty_delta / stock_balances)
--   * rate_paise is paise PER BASE UNIT
--   * line_total_paise = round(qty * rate_paise)
-- The UI converts a purchase-unit entry (e.g. "2 bags") to base units via
-- toBaseQty(qty, conversion_factor) BEFORE calling this RPC.
--
-- Idempotency (§4.4): a client-generated (device_id, idempotency_key) pair makes
-- an offline-synced/retried post replay-safe — a second call with the same key
-- returns the already-stored purchase instead of double-posting stock.
-- ============================================================================

-- ---- idempotency_keys (reusable across all offline-synced RPCs) -------------
create table public.idempotency_keys (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  device_id       text not null,
  idempotency_key text not null,
  operation       text not null,
  result_id       uuid not null,
  created_by      uuid references public.users(id),
  created_at      timestamptz not null default now(),
  unique (device_id, idempotency_key)
);
create index idx_idempotency_keys_org_id on public.idempotency_keys(org_id);

alter table public.idempotency_keys enable row level security;

-- Append-only for clients: written (as the calling user) by the RPCs; read back
-- for replay. Never updated or deleted by clients.
grant select, insert on public.idempotency_keys to authenticated;
revoke update, delete on public.idempotency_keys from anon, authenticated;

create policy "idem_select" on public.idempotency_keys for select to authenticated
  using (org_id = private.current_org_id());
create policy "idem_insert" on public.idempotency_keys for insert to authenticated
  with check (org_id = private.current_org_id());

-- ---- post_purchase RPC -----------------------------------------------------
create or replace function public.post_purchase(
  p_location_id      uuid,
  p_supplier_id      uuid,
  p_purchase_date    date,
  p_payment_status   public.purchase_payment_status,
  p_items            jsonb,
  p_shift_session_id uuid  default null,
  p_notes            text  default null,
  p_device_id        text  default null,
  p_idempotency_key  text  default null
) returns public.purchases
language plpgsql
as $$
declare
  v_org      uuid;
  v_uid      uuid := (select auth.uid());
  v_purchase public.purchases;
  v_existing uuid;
  v_item     record;
  v_line     bigint;
  v_total    bigint := 0;
  v_count    integer := 0;
begin
  -- Idempotent replay: a prior post with this key returns its stored purchase
  -- (re-read through RLS so the caller only sees rows they may access).
  if p_idempotency_key is not null then
    if p_device_id is null then
      raise exception 'device_id is required when an idempotency_key is given'
        using errcode = '22023';
    end if;
    select result_id into v_existing from public.idempotency_keys
    where device_id = p_device_id and idempotency_key = p_idempotency_key;
    if found then
      select * into v_purchase from public.purchases where id = v_existing;
      return v_purchase;
    end if;
  end if;

  -- Derive org from the target location (RLS makes it visible only to members
  -- with access); a null result means no access / unknown location.
  select org_id into v_org from public.locations where id = p_location_id;
  if v_org is null then
    raise exception 'location not found or not accessible' using errcode = 'P0002';
  end if;

  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'items must be a JSON array' using errcode = '22023';
  end if;

  -- Header first (RLS insert policy enforces has_location_access + org match).
  insert into public.purchases
    (org_id, location_id, supplier_id, purchase_date, payment_status,
     shift_session_id, notes, total_paise, created_by)
  values
    (v_org, p_location_id, p_supplier_id, p_purchase_date, p_payment_status,
     p_shift_session_id, p_notes, 0, v_uid)
  returning * into v_purchase;

  for v_item in
    select * from jsonb_to_recordset(p_items)
      as x(item_id uuid, qty numeric, rate_paise bigint)
  loop
    v_count := v_count + 1;
    if v_item.item_id is null then
      raise exception 'each line needs an item_id' using errcode = '22023';
    end if;
    if v_item.qty is null or v_item.qty <= 0 then
      raise exception 'line qty must be greater than zero' using errcode = '23514';
    end if;
    if v_item.rate_paise is null or v_item.rate_paise < 0 then
      raise exception 'line rate cannot be negative' using errcode = '23514';
    end if;
    -- Reject items outside the caller's org (RLS makes foreign rows invisible).
    perform 1 from public.stock_items where id = v_item.item_id and org_id = v_org;
    if not found then
      raise exception 'stock item % not found in this org', v_item.item_id
        using errcode = 'P0002';
    end if;

    v_line  := round(v_item.qty * v_item.rate_paise)::bigint;
    v_total := v_total + v_line;

    insert into public.purchase_items
      (org_id, location_id, purchase_id, item_id, qty, rate_paise, line_total_paise)
    values
      (v_org, p_location_id, v_purchase.id, v_item.item_id, v_item.qty,
       v_item.rate_paise, v_line);

    -- Append-only ledger movement; the balance trigger updates stock_balances.
    insert into public.stock_movements
      (org_id, location_id, item_id, movement_type, qty_delta, rate_paise,
       ref_table, ref_id, shift_session_id, created_by)
    values
      (v_org, p_location_id, v_item.item_id, 'purchase', v_item.qty,
       v_item.rate_paise, 'purchases', v_purchase.id, p_shift_session_id, v_uid);
  end loop;

  if v_count = 0 then
    raise exception 'a purchase needs at least one line item' using errcode = '22023';
  end if;

  update public.purchases set total_paise = v_total, updated_at = now()
  where id = v_purchase.id
  returning * into v_purchase;

  if p_idempotency_key is not null then
    insert into public.idempotency_keys
      (org_id, device_id, idempotency_key, operation, result_id, created_by)
    values
      (v_org, p_device_id, p_idempotency_key, 'post_purchase', v_purchase.id, v_uid);
  end if;

  return v_purchase;
end $$;

grant execute on function
  public.post_purchase(uuid, uuid, date, public.purchase_payment_status, jsonb,
                       uuid, text, text, text)
  to authenticated;
