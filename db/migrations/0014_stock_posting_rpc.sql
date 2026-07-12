-- ============================================================================
-- Migration 0014 — Transactional stock-posting RPCs (§4.4)
-- The stock family promised in 0006: purchases, consumption, and waste each
-- write a source row AND its append-only stock_movements in ONE Postgres
-- transaction (one RPC = one txn). All are SECURITY INVOKER, so the caller's
-- RLS applies to every statement — an admin can only post at their own
-- locations, and the negative-stock guard on stock_movements (0005) still fires.
--
-- Idempotency (§4.4): every offline-synced / retryable mutation carries a
-- client-generated (device_id, idempotency_key). The first call records the
-- result; a replay returns the stored result verbatim and posts nothing new.
-- UNIQUE(device_id, idempotency_key) + ON CONFLICT DO NOTHING is the guard, so
-- a flaky network or an offline queue drain can never double-post a purchase,
-- a consumption, or a waste entry.
-- ============================================================================

-- ---- idempotency_keys ------------------------------------------------------
create table public.idempotency_keys (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  device_id       text not null,
  idempotency_key uuid not null,
  operation       text not null,
  result          jsonb,
  created_by      uuid references public.users(id),
  created_at      timestamptz not null default now(),
  unique (device_id, idempotency_key)
);
create index idx_idempotency_keys_org_id on public.idempotency_keys(org_id);

alter table public.idempotency_keys enable row level security;
-- Written only inside the SECURITY INVOKER RPCs below; never updated/deleted by
-- clients (a recorded result is immutable — that is what makes replay safe).
grant select, insert, update on public.idempotency_keys to authenticated;
revoke delete on public.idempotency_keys from anon, authenticated;

create policy "idem_select" on public.idempotency_keys for select to authenticated
  using (org_id = private.current_org_id());
create policy "idem_insert" on public.idempotency_keys for insert to authenticated
  with check (org_id = private.current_org_id());
-- UPDATE only to fill in the result of a row this caller just inserted; scoped
-- to the org and only while the result is still null (write-once).
create policy "idem_update" on public.idempotency_keys for update to authenticated
  using (org_id = private.current_org_id() and result is null)
  with check (org_id = private.current_org_id());

-- ---- idem_begin (public: authenticated has no USAGE on the private schema) --
-- Reserve an idempotency slot. Returns the slot id when this is the first call
-- (caller then does its work and stores the result); returns NULL when it is a
-- replay, with the stored result in the OUT param. On a concurrent in-flight
-- first call, ON CONFLICT DO NOTHING blocks until that txn commits, then this
-- call sees the committed row and replays it. SECURITY INVOKER: the slot insert
-- runs under the caller's RLS, so the org check on idempotency_keys applies.
create or replace function public.idem_begin(
  p_org_id     uuid,
  p_device_id  text,
  p_key        uuid,
  p_operation  text,
  out slot_id  uuid,
  out replayed jsonb
)
language plpgsql security invoker as $$
declare
  v_op text;
begin
  insert into public.idempotency_keys (org_id, device_id, idempotency_key, operation, created_by)
  values (p_org_id, p_device_id, p_key, p_operation, (select auth.uid()))
  on conflict (device_id, idempotency_key) do nothing
  returning id into slot_id;

  if slot_id is null then
    -- Replay: a committed slot always carries a non-null result (the original
    -- txn set it before commit; on error the whole txn — slot included — rolls
    -- back). Guard against a mismatched operation reusing the same key.
    select operation, result into v_op, replayed
    from public.idempotency_keys
    where device_id = p_device_id and idempotency_key = p_key;
    if v_op is distinct from p_operation then
      raise exception 'idempotency key reused for a different operation (% vs %)', v_op, p_operation
        using errcode = '23505';
    end if;
  end if;
end $$;

grant execute on function public.idem_begin(uuid, text, uuid, text) to authenticated;

-- ---- post_purchase ---------------------------------------------------------
-- p_items: jsonb array of {item_id, qty, rate_paise} where qty is in the item's
-- PURCHASE unit and rate_paise is per purchase unit. The purchase_items row is
-- stored as entered; the stock_movement is converted to BASE units via the
-- item's conversion_factor (base_qty = qty × factor; base rate = line / base).
create or replace function public.post_purchase(
  p_device_id       text,
  p_idempotency_key uuid,
  p_location_id     uuid,
  p_supplier_id     uuid,
  p_purchase_date   date,
  p_payment_status  public.purchase_payment_status,
  p_shift_session_id uuid,
  p_notes           text,
  p_items           jsonb
) returns jsonb
language plpgsql security invoker as $$
declare
  v_org        uuid;
  v_slot       uuid;
  v_replay     jsonb;
  v_purchase   uuid;
  v_total      bigint := 0;
  v_elem       jsonb;
  v_item       uuid;
  v_qty        numeric(12,3);
  v_rate       bigint;
  v_line       bigint;
  v_factor     numeric(12,4);
  v_base_qty   numeric(12,3);
  v_base_rate  bigint;
begin
  -- Caller's org from their own membership (RLS-readable; avoids a private-schema
  -- call, which authenticated cannot resolve from a SECURITY INVOKER body).
  select org_id into v_org from public.memberships
  where user_id = (select auth.uid()) limit 1;

  select slot_id, replayed into v_slot, v_replay
  from public.idem_begin(v_org, p_device_id, p_idempotency_key, 'post_purchase');
  if v_slot is null then return v_replay; end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'purchase must have at least one line item' using errcode = '23514';
  end if;

  insert into public.purchases
    (org_id, location_id, supplier_id, purchase_date, payment_status,
     total_paise, shift_session_id, notes, created_by)
  values
    (v_org, p_location_id, p_supplier_id, p_purchase_date, p_payment_status,
     0, p_shift_session_id, p_notes, (select auth.uid()))
  returning id into v_purchase;

  for v_elem in select * from jsonb_array_elements(p_items) loop
    v_item := (v_elem->>'item_id')::uuid;
    v_qty  := (v_elem->>'qty')::numeric;
    v_rate := (v_elem->>'rate_paise')::bigint;
    if v_qty < 0 or v_rate < 0 then
      raise exception 'qty and rate must be non-negative' using errcode = '23514';
    end if;

    select conversion_factor into v_factor from public.stock_items where id = v_item;
    if v_factor is null then
      raise exception 'stock item % not found or not accessible', v_item using errcode = 'P0002';
    end if;

    v_line     := round(v_qty * v_rate);
    v_base_qty := round(v_qty * v_factor, 3);
    v_base_rate := case when v_base_qty > 0 then round(v_line / v_base_qty) else 0 end;
    v_total    := v_total + v_line;

    insert into public.purchase_items
      (org_id, location_id, purchase_id, item_id, qty, rate_paise, line_total_paise)
    values (v_org, p_location_id, v_purchase, v_item, v_qty, v_rate, v_line);

    insert into public.stock_movements
      (org_id, location_id, item_id, movement_type, qty_delta, rate_paise,
       ref_table, ref_id, shift_session_id, created_by)
    values (v_org, p_location_id, v_item, 'purchase', v_base_qty, v_base_rate,
       'purchases', v_purchase, p_shift_session_id, (select auth.uid()));
  end loop;

  update public.purchases set total_paise = v_total where id = v_purchase;

  v_replay := jsonb_build_object('purchase_id', v_purchase, 'total_paise', v_total);
  update public.idempotency_keys set result = v_replay where id = v_slot;
  return v_replay;
end $$;

grant execute on function
  public.post_purchase(text, uuid, uuid, uuid, date, public.purchase_payment_status, uuid, text, jsonb)
  to authenticated;

-- ---- post_consumption ------------------------------------------------------
-- p_items: jsonb array of {item_id, qty} where qty is in BASE units. Posts one
-- 'consumption' movement per item (negative delta), valued at standard rate.
-- The negative-stock guard rejects the whole transaction if any line overdraws.
create or replace function public.post_consumption(
  p_device_id        text,
  p_idempotency_key  uuid,
  p_location_id      uuid,
  p_shift_session_id uuid,
  p_note             text,
  p_items            jsonb
) returns jsonb
language plpgsql security invoker as $$
declare
  v_org     uuid;
  v_slot    uuid;
  v_replay  jsonb;
  v_elem    jsonb;
  v_item    uuid;
  v_qty     numeric(12,3);
  v_rate    bigint;
  v_value   bigint := 0;
  v_count   integer := 0;
begin
  -- Caller's org from their own membership (RLS-readable; avoids a private-schema
  -- call, which authenticated cannot resolve from a SECURITY INVOKER body).
  select org_id into v_org from public.memberships
  where user_id = (select auth.uid()) limit 1;

  select slot_id, replayed into v_slot, v_replay
  from public.idem_begin(v_org, p_device_id, p_idempotency_key, 'post_consumption');
  if v_slot is null then return v_replay; end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'consumption must have at least one line item' using errcode = '23514';
  end if;

  for v_elem in select * from jsonb_array_elements(p_items) loop
    v_item := (v_elem->>'item_id')::uuid;
    v_qty  := (v_elem->>'qty')::numeric;
    if v_qty <= 0 then
      raise exception 'consumption qty must be positive' using errcode = '23514';
    end if;

    select standard_rate_paise into v_rate from public.stock_items where id = v_item;
    if v_rate is null then
      raise exception 'stock item % not found or not accessible', v_item using errcode = 'P0002';
    end if;

    insert into public.stock_movements
      (org_id, location_id, item_id, movement_type, qty_delta, rate_paise,
       ref_table, shift_session_id, note, created_by)
    values (v_org, p_location_id, v_item, 'consumption', -v_qty, v_rate,
       'consumption', p_shift_session_id, p_note, (select auth.uid()));

    v_value := v_value + round(v_qty * v_rate);
    v_count := v_count + 1;
  end loop;

  v_replay := jsonb_build_object('items', v_count, 'value_paise', v_value);
  update public.idempotency_keys set result = v_replay where id = v_slot;
  return v_replay;
end $$;

grant execute on function
  public.post_consumption(text, uuid, uuid, uuid, text, jsonb) to authenticated;

-- ---- post_waste ------------------------------------------------------------
-- One waste_log row + one 'waste' movement (negative delta). Cost defaults to
-- qty × standard rate when p_cost_paise is null. qty is in BASE units.
create or replace function public.post_waste(
  p_device_id        text,
  p_idempotency_key  uuid,
  p_location_id      uuid,
  p_item_id          uuid,
  p_qty              numeric,
  p_reason_code      public.waste_reason,
  p_shift_session_id uuid,
  p_cost_paise       bigint,
  p_note             text
) returns jsonb
language plpgsql security invoker as $$
declare
  v_org   uuid;
  v_slot  uuid;
  v_replay jsonb;
  v_rate  bigint;
  v_cost  bigint;
  v_waste uuid;
begin
  -- Caller's org from their own membership (RLS-readable; avoids a private-schema
  -- call, which authenticated cannot resolve from a SECURITY INVOKER body).
  select org_id into v_org from public.memberships
  where user_id = (select auth.uid()) limit 1;

  select slot_id, replayed into v_slot, v_replay
  from public.idem_begin(v_org, p_device_id, p_idempotency_key, 'post_waste');
  if v_slot is null then return v_replay; end if;

  if p_qty <= 0 then
    raise exception 'waste qty must be positive' using errcode = '23514';
  end if;

  select standard_rate_paise into v_rate from public.stock_items where id = p_item_id;
  if v_rate is null then
    raise exception 'stock item % not found or not accessible', p_item_id using errcode = 'P0002';
  end if;
  v_cost := coalesce(p_cost_paise, round(p_qty * v_rate));

  insert into public.waste_logs
    (org_id, location_id, item_id, qty, reason_code, shift_session_id, cost_paise, note, created_by)
  values (v_org, p_location_id, p_item_id, p_qty, p_reason_code, p_shift_session_id,
     v_cost, p_note, (select auth.uid()))
  returning id into v_waste;

  insert into public.stock_movements
    (org_id, location_id, item_id, movement_type, qty_delta, rate_paise,
     ref_table, ref_id, shift_session_id, note, created_by)
  values (v_org, p_location_id, p_item_id, 'waste', -p_qty, v_rate,
     'waste_logs', v_waste, p_shift_session_id, p_note, (select auth.uid()));

  v_replay := jsonb_build_object('waste_id', v_waste, 'cost_paise', v_cost);
  update public.idempotency_keys set result = v_replay where id = v_slot;
  return v_replay;
end $$;

grant execute on function
  public.post_waste(text, uuid, uuid, uuid, numeric, public.waste_reason, uuid, bigint, text)
  to authenticated;
