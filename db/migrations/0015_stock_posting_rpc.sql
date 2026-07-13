-- ============================================================================
-- Migration 0015 — Stock posting RPCs (§4.4): consumption, waste, count finalize
--
-- Each is one transaction of append-only stock_movements (+ its source rows).
-- SECURITY INVOKER: the caller's RLS applies to every statement, and org_id is
-- derived from the target location row (never from a direct `private` call —
-- authenticated has no USAGE on that schema; helpers run only inside RLS).
--
-- The negative-stock guard in private.apply_stock_movement() (0005) rejects any
-- consumption/waste that would drive a balance below zero, rolling back the
-- whole batch. Idempotency reuses idempotency_keys (0014): every batch gets a
-- generated batch id stamped on ref_id, stored as the key's result, so a replay
-- returns the same batch instead of double-posting.
-- ============================================================================

-- ---- shared: resolve org from an accessible location -----------------------
-- (kept inline in each function; a helper would live in `private` and need the
--  same USAGE that we are deliberately avoiding, so we repeat the two lines.)

-- batch_id groups the waste_logs written by one post_waste call, so an
-- idempotent replay can return exactly that batch's rows.
alter table public.waste_logs add column batch_id uuid;
create index idx_waste_logs_batch_id on public.waste_logs(batch_id);

-- ---- post_consumption ------------------------------------------------------
-- p_items: [{"item_id": uuid, "qty": numeric}] — qty in BASE units, consumed
-- (posted as negative deltas). Templates are expanded client-side into p_items.
create or replace function public.post_consumption(
  p_location_id      uuid,
  p_shift_session_id uuid,
  p_items            jsonb,
  p_note             text default null,
  p_device_id        text default null,
  p_idempotency_key  text default null
) returns setof public.stock_movements
language plpgsql
as $$
declare
  v_org   uuid;
  v_uid   uuid := (select auth.uid());
  v_batch uuid;
  v_item  record;
  v_count integer := 0;
begin
  if p_idempotency_key is not null then
    if p_device_id is null then
      raise exception 'device_id is required when an idempotency_key is given'
        using errcode = '22023';
    end if;
    select result_id into v_batch from public.idempotency_keys
    where device_id = p_device_id and idempotency_key = p_idempotency_key;
    if found then
      return query select * from public.stock_movements
        where ref_table = 'consumption' and ref_id = v_batch;
      return;
    end if;
  end if;

  select org_id into v_org from public.locations where id = p_location_id;
  if v_org is null then
    raise exception 'location not found or not accessible' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'items must be a JSON array' using errcode = '22023';
  end if;

  v_batch := gen_random_uuid();

  for v_item in
    select * from jsonb_to_recordset(p_items) as x(item_id uuid, qty numeric)
  loop
    v_count := v_count + 1;
    if v_item.item_id is null then
      raise exception 'each line needs an item_id' using errcode = '22023';
    end if;
    if v_item.qty is null or v_item.qty <= 0 then
      raise exception 'consumption qty must be greater than zero' using errcode = '23514';
    end if;
    perform 1 from public.stock_items where id = v_item.item_id and org_id = v_org;
    if not found then
      raise exception 'stock item % not found in this org', v_item.item_id
        using errcode = 'P0002';
    end if;

    insert into public.stock_movements
      (org_id, location_id, item_id, movement_type, qty_delta,
       ref_table, ref_id, shift_session_id, note, created_by)
    values
      (v_org, p_location_id, v_item.item_id, 'consumption', -v_item.qty,
       'consumption', v_batch, p_shift_session_id, p_note, v_uid);
  end loop;

  if v_count = 0 then
    raise exception 'consumption needs at least one line item' using errcode = '22023';
  end if;

  if p_idempotency_key is not null then
    insert into public.idempotency_keys
      (org_id, device_id, idempotency_key, operation, result_id, created_by)
    values
      (v_org, p_device_id, p_idempotency_key, 'post_consumption', v_batch, v_uid);
  end if;

  return query select * from public.stock_movements
    where ref_table = 'consumption' and ref_id = v_batch;
end $$;

-- ---- post_waste ------------------------------------------------------------
-- p_items: [{"item_id": uuid, "qty": numeric, "reason_code": text,
--            "cost_paise": bigint}] — writes a waste_log + a negative movement
-- per line. cost_paise defaults to qty * item.standard_rate_paise when omitted.
create or replace function public.post_waste(
  p_location_id      uuid,
  p_shift_session_id uuid,
  p_items            jsonb,
  p_device_id        text default null,
  p_idempotency_key  text default null
) returns setof public.waste_logs
language plpgsql
as $$
declare
  v_org      uuid;
  v_uid      uuid := (select auth.uid());
  v_batch    uuid;
  v_item     record;
  v_cost     bigint;
  v_std      bigint;
  v_waste_id uuid;
  v_count    integer := 0;
begin
  if p_idempotency_key is not null then
    if p_device_id is null then
      raise exception 'device_id is required when an idempotency_key is given'
        using errcode = '22023';
    end if;
    select result_id into v_batch from public.idempotency_keys
    where device_id = p_device_id and idempotency_key = p_idempotency_key;
    if found then
      return query select * from public.waste_logs where batch_id = v_batch;
      return;
    end if;
  end if;

  select org_id into v_org from public.locations where id = p_location_id;
  if v_org is null then
    raise exception 'location not found or not accessible' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'items must be a JSON array' using errcode = '22023';
  end if;

  v_batch := gen_random_uuid();

  for v_item in
    select * from jsonb_to_recordset(p_items)
      as x(item_id uuid, qty numeric, reason_code public.waste_reason, cost_paise bigint)
  loop
    v_count := v_count + 1;
    if v_item.item_id is null or v_item.reason_code is null then
      raise exception 'each line needs an item_id and reason_code' using errcode = '22023';
    end if;
    if v_item.qty is null or v_item.qty <= 0 then
      raise exception 'waste qty must be greater than zero' using errcode = '23514';
    end if;
    if v_item.cost_paise is not null and v_item.cost_paise < 0 then
      raise exception 'waste cost cannot be negative' using errcode = '23514';
    end if;
    select standard_rate_paise into v_std from public.stock_items
    where id = v_item.item_id and org_id = v_org;
    if not found then
      raise exception 'stock item % not found in this org', v_item.item_id
        using errcode = 'P0002';
    end if;
    v_cost := coalesce(v_item.cost_paise, round(v_item.qty * v_std)::bigint);

    insert into public.waste_logs
      (org_id, location_id, item_id, qty, reason_code, shift_session_id,
       cost_paise, batch_id, created_by)
    values
      (v_org, p_location_id, v_item.item_id, v_item.qty, v_item.reason_code,
       p_shift_session_id, v_cost, v_batch, v_uid)
    returning id into v_waste_id;

    insert into public.stock_movements
      (org_id, location_id, item_id, movement_type, qty_delta, rate_paise,
       ref_table, ref_id, shift_session_id, created_by)
    values
      (v_org, p_location_id, v_item.item_id, 'waste', -v_item.qty, v_std,
       'waste_logs', v_waste_id, p_shift_session_id, v_uid);
  end loop;

  if v_count = 0 then
    raise exception 'waste needs at least one line item' using errcode = '22023';
  end if;

  if p_idempotency_key is not null then
    insert into public.idempotency_keys
      (org_id, device_id, idempotency_key, operation, result_id, created_by)
    values
      (v_org, p_device_id, p_idempotency_key, 'post_waste', v_batch, v_uid);
  end if;

  return query select * from public.waste_logs where batch_id = v_batch;
end $$;

-- ---- finalize_stock_count --------------------------------------------------
-- Snapshots system_qty from stock_balances for each count line, computes the
-- variance against the entered counted_qty, posts a signed 'adjustment' movement
-- for every non-zero variance, and flips the count draft -> posted. This is the
-- shrinkage-proving reconciliation (§4.4). Idempotent by count status: a second
-- call on an already-posted count is rejected.
create or replace function public.finalize_stock_count(p_count_id uuid)
returns public.stock_counts
language plpgsql
as $$
declare
  v_count public.stock_counts;
  v_org   uuid;
  v_uid   uuid := (select auth.uid());
  v_line  record;
  v_sys   numeric(12,3);
  v_var   numeric(12,3);
  v_std   bigint;
begin
  select * into v_count from public.stock_counts where id = p_count_id for update;
  if not found then
    raise exception 'stock count not found or not accessible' using errcode = 'P0002';
  end if;
  if v_count.status <> 'draft' then
    raise exception 'stock count is already posted' using errcode = 'P0001';
  end if;
  v_org := v_count.org_id;

  for v_line in
    select * from public.stock_count_items where count_id = p_count_id
  loop
    select coalesce(qty, 0) into v_sys from public.stock_balances
    where location_id = v_count.location_id and item_id = v_line.item_id;
    v_sys := coalesce(v_sys, 0);
    v_var := round((v_line.counted_qty - v_sys)::numeric, 3);

    select standard_rate_paise into v_std from public.stock_items where id = v_line.item_id;

    update public.stock_count_items set
      system_qty           = v_sys,
      variance_qty         = v_var,
      variance_value_paise = round(v_var * coalesce(v_std, 0))::bigint
    where id = v_line.id;

    if v_var <> 0 then
      insert into public.stock_movements
        (org_id, location_id, item_id, movement_type, qty_delta, rate_paise,
         ref_table, ref_id, note, created_by)
      values
        (v_org, v_count.location_id, v_line.item_id, 'adjustment', v_var,
         v_std, 'stock_counts', p_count_id, v_line.reason, v_uid);
    end if;
  end loop;

  update public.stock_counts set status = 'posted', updated_at = now()
  where id = p_count_id
  returning * into v_count;

  return v_count;
end $$;

grant execute on function
  public.post_consumption(uuid, uuid, jsonb, text, text, text) to authenticated;
grant execute on function
  public.post_waste(uuid, uuid, jsonb, text, text) to authenticated;
grant execute on function
  public.finalize_stock_count(uuid) to authenticated;
