-- ============================================================================
-- Migration 0016 — Hostel RPCs (§4.4): rent payment allocation + move-out
--
-- SECURITY INVOKER; org/location derived from the tenant/moveout row (RLS makes
-- them visible only to members with access — no direct `private` calls).
--
-- record_rent_payment mirrors lib/money.ts allocateOldestFirst: a payment is
-- applied oldest-invoice-first, fully clearing earlier invoices before later
-- ones, updating each invoice status due/partial/paid. An overpayment beyond
-- all open invoices is rejected (no phantom advance row — there is no advance
-- ledger in the schema yet) so money is never silently dropped. Batch-idempotent.
--
-- settle_moveout mirrors depositRefundPaise: refund = deposit held − damages −
-- dues. The status → approved transition is gated to super_admin by the
-- enforce_moveout_approval trigger (0008); an admin call raises 42501.
-- ============================================================================

-- batch_id groups the rent_payments written by one record_rent_payment call so
-- an idempotent replay returns exactly that batch.
alter table public.rent_payments add column batch_id uuid;
create index idx_rent_payments_batch_id on public.rent_payments(batch_id);

-- ---- record_rent_payment ---------------------------------------------------
create or replace function public.record_rent_payment(
  p_tenant_id       uuid,
  p_amount_paise    bigint,
  p_paid_date       date,
  p_mode            public.rent_payment_mode,
  p_device_id       text default null,
  p_idempotency_key text default null
) returns setof public.rent_payments
language plpgsql
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_org       uuid;
  v_loc       uuid;
  v_batch     uuid;
  v_remaining bigint := p_amount_paise;
  v_apply     bigint;
  v_inv       record;
begin
  if p_idempotency_key is not null then
    if p_device_id is null then
      raise exception 'device_id is required when an idempotency_key is given'
        using errcode = '22023';
    end if;
    select result_id into v_batch from public.idempotency_keys
    where device_id = p_device_id and idempotency_key = p_idempotency_key;
    if found then
      return query select * from public.rent_payments where batch_id = v_batch;
      return;
    end if;
  end if;

  select org_id, location_id into v_org, v_loc
  from public.tenants where id = p_tenant_id;
  if not found then
    raise exception 'tenant not found or not accessible' using errcode = 'P0002';
  end if;
  if p_amount_paise <= 0 then
    raise exception 'payment amount must be greater than zero' using errcode = '23514';
  end if;

  v_batch := gen_random_uuid();

  -- Oldest-first over the tenant's open invoices; balance = total − non-reversed
  -- payments so far. The FOR snapshot is stable while we insert inside the loop.
  for v_inv in
    select i.id,
           i.total_paise - coalesce(p.paid, 0) as balance
    from public.rent_invoices i
    left join (
      select invoice_id, sum(amount_paise) as paid
      from public.rent_payments where reversed = false group by invoice_id
    ) p on p.invoice_id = i.id
    where i.tenant_id = p_tenant_id and i.status in ('due', 'partial')
    order by i.due_date, i.period
  loop
    exit when v_remaining <= 0;
    v_apply := least(v_remaining, greatest(v_inv.balance, 0));
    if v_apply <= 0 then
      continue;
    end if;

    insert into public.rent_payments
      (org_id, location_id, invoice_id, amount_paise, paid_date, mode,
       confirmed_by, batch_id, created_by)
    values
      (v_org, v_loc, v_inv.id, v_apply, p_paid_date, p_mode, v_uid, v_batch, v_uid);

    update public.rent_invoices
      set status = (case when v_apply >= v_inv.balance then 'paid' else 'partial' end)::public.rent_invoice_status
    where id = v_inv.id;

    v_remaining := v_remaining - v_apply;
  end loop;

  if v_remaining > 0 then
    raise exception 'payment exceeds outstanding by % paise; create the next invoice first', v_remaining
      using errcode = 'P0001';
  end if;

  if p_idempotency_key is not null then
    insert into public.idempotency_keys
      (org_id, device_id, idempotency_key, operation, result_id, created_by)
    values
      (v_org, p_device_id, p_idempotency_key, 'record_rent_payment', v_batch, v_uid);
  end if;

  return query select * from public.rent_payments where batch_id = v_batch;
end $$;

-- ---- settle_moveout --------------------------------------------------------
create or replace function public.settle_moveout(p_moveout_id uuid)
returns public.moveouts
language plpgsql
as $$
declare
  v_mo     public.moveouts;
  v_uid    uuid := (select auth.uid());
  v_held   bigint;
  v_refund bigint;
begin
  select * into v_mo from public.moveouts where id = p_moveout_id for update;
  if not found then
    raise exception 'move-out not found or not accessible' using errcode = 'P0002';
  end if;
  if v_mo.status <> 'pending' then
    raise exception 'move-out is already settled' using errcode = 'P0001';
  end if;

  -- Net deposit held = received − deduction − refund to date.
  select coalesce(sum(case type
                        when 'received'  then amount_paise
                        when 'deduction' then -amount_paise
                        when 'refund'    then -amount_paise end), 0)
  into v_held
  from public.deposit_transactions where tenant_id = v_mo.tenant_id;

  v_refund := v_held - v_mo.damages_paise - v_mo.dues_paise;

  -- Record damages as a deduction against the deposit ledger (if any).
  if v_mo.damages_paise > 0 then
    insert into public.deposit_transactions
      (org_id, location_id, tenant_id, type, amount_paise, description, created_by)
    values
      (v_mo.org_id, v_mo.location_id, v_mo.tenant_id, 'deduction',
       v_mo.damages_paise, 'move-out damages', v_uid);
  end if;

  -- Record the refund owed to the tenant (only when positive).
  if v_refund > 0 then
    insert into public.deposit_transactions
      (org_id, location_id, tenant_id, type, amount_paise, description, created_by)
    values
      (v_mo.org_id, v_mo.location_id, v_mo.tenant_id, 'refund',
       v_refund, 'move-out settlement refund', v_uid);
  end if;

  -- status -> approved is super_admin-gated by the trigger (raises 42501 for admin).
  update public.moveouts
    set refund_paise = v_refund, status = 'approved', approved_by = v_uid
  where id = p_moveout_id
  returning * into v_mo;

  update public.tenants set status = 'vacated' where id = v_mo.tenant_id;

  return v_mo;
end $$;

grant execute on function
  public.record_rent_payment(uuid, bigint, date, public.rent_payment_mode, text, text)
  to authenticated;
grant execute on function public.settle_moveout(uuid) to authenticated;
