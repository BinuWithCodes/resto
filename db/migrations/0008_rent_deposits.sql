-- ============================================================================
-- Migration 0008 — Rent, payments, reminders, deposits, move-out (Phase 2)
-- Location-scoped. Money in bigint paise. Receipt numbers unique per location.
-- Move-out settlement approval is super_admin-only (§1.1), enforced by a
-- trigger. Rent receipts are simple receipts, not tax invoices (§7, no GST).
-- ============================================================================

create type public.rent_invoice_status as enum ('due', 'partial', 'paid', 'waived');
create type public.rent_payment_mode   as enum ('upi', 'cash', 'bank');
create type public.reminder_stage      as enum ('t_minus_3', 't0', 't3', 't7', 't15');
create type public.deposit_txn_type    as enum ('received', 'deduction', 'refund');
create type public.moveout_status      as enum ('pending', 'approved', 'completed');

-- ---- rent_invoices ---------------------------------------------------------
create table public.rent_invoices (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null references public.organizations(id) on delete cascade,
  location_id       uuid not null references public.locations(id) on delete restrict,
  tenant_id         uuid not null references public.tenants(id) on delete restrict,
  period            text not null,                         -- e.g. '2026-07'
  due_date          date not null,
  base_rent_paise   bigint not null default 0 check (base_rent_paise >= 0),
  utility_paise     bigint not null default 0 check (utility_paise >= 0),
  meal_paise        bigint not null default 0 check (meal_paise >= 0),
  late_fee_paise    bigint not null default 0 check (late_fee_paise >= 0),
  adjustment_paise  bigint not null default 0,             -- signed (discount/credit)
  total_paise       bigint not null default 0,
  status            public.rent_invoice_status not null default 'due',
  receipt_no        text,
  created_by        uuid references public.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (tenant_id, period)
);
create index idx_rent_invoices_location_id on public.rent_invoices(location_id);
create index idx_rent_invoices_org_id on public.rent_invoices(org_id);
create index idx_rent_invoices_tenant_id on public.rent_invoices(tenant_id);
create index idx_rent_invoices_status on public.rent_invoices(status);
create unique index uq_rent_invoices_receipt
  on public.rent_invoices(location_id, receipt_no) where receipt_no is not null;

-- ---- rent_payments ---------------------------------------------------------
create table public.rent_payments (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations(id) on delete cascade,
  location_id     uuid not null references public.locations(id) on delete restrict,
  invoice_id      uuid not null references public.rent_invoices(id) on delete restrict,
  amount_paise    bigint not null check (amount_paise >= 0),
  paid_date       date not null,
  mode            public.rent_payment_mode not null,
  confirmed_by    uuid references public.users(id),
  reversed        boolean not null default false,
  reversal_reason text,
  created_by      uuid references public.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index idx_rent_payments_invoice_id on public.rent_payments(invoice_id);
create index idx_rent_payments_location_id on public.rent_payments(location_id);
create index idx_rent_payments_org_id on public.rent_payments(org_id);

-- ---- reminder_logs ---------------------------------------------------------
create table public.reminder_logs (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  invoice_id  uuid references public.rent_invoices(id) on delete set null,
  stage       public.reminder_stage not null,
  sent_at     timestamptz not null default now(),
  sent_by     uuid references public.users(id)
);
create index idx_reminder_logs_tenant_id on public.reminder_logs(tenant_id);
create index idx_reminder_logs_location_id on public.reminder_logs(location_id);

-- ---- deposit_transactions --------------------------------------------------
create table public.deposit_transactions (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations(id) on delete cascade,
  location_id  uuid not null references public.locations(id) on delete restrict,
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  type         public.deposit_txn_type not null,
  amount_paise bigint not null check (amount_paise >= 0),
  description  text,
  created_by   uuid references public.users(id),
  created_at   timestamptz not null default now()
);
create index idx_deposit_txn_tenant_id on public.deposit_transactions(tenant_id);
create index idx_deposit_txn_location_id on public.deposit_transactions(location_id);
create index idx_deposit_txn_org_id on public.deposit_transactions(org_id);

-- ---- moveouts --------------------------------------------------------------
create table public.moveouts (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations(id) on delete cascade,
  location_id      uuid not null references public.locations(id) on delete restrict,
  tenant_id        uuid not null references public.tenants(id) on delete restrict,
  notice_date      date,
  vacate_date      date,
  inspection_notes text,
  dues_paise       bigint not null default 0 check (dues_paise >= 0),
  damages_paise    bigint not null default 0 check (damages_paise >= 0),
  refund_paise     bigint not null default 0,
  status           public.moveout_status not null default 'pending',
  approved_by      uuid references public.users(id),
  created_by       uuid references public.users(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (tenant_id)
);
create index idx_moveouts_location_id on public.moveouts(location_id);
create index idx_moveouts_org_id on public.moveouts(org_id);

-- ---- Move-out approval is super_admin-only (§1.1) --------------------------
create or replace function private.enforce_moveout_approval()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status in ('approved', 'completed')
     and (old.status is distinct from new.status)
     and not private.is_super_admin() then
    raise exception 'move-out settlement requires super_admin approval'
      using errcode = '42501';
  end if;
  return new;
end $$;

create trigger moveout_approval_guard before update on public.moveouts
  for each row execute function private.enforce_moveout_approval();

-- ---- triggers --------------------------------------------------------------
create trigger set_updated_at before update on public.rent_invoices
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.rent_payments
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.moveouts
  for each row execute function private.set_updated_at();

create trigger audit_rent_invoices after insert or update or delete on public.rent_invoices
  for each row execute function private.audit_trigger();
create trigger audit_rent_payments after insert or update or delete on public.rent_payments
  for each row execute function private.audit_trigger();
create trigger audit_deposit_txn after insert or update or delete on public.deposit_transactions
  for each row execute function private.audit_trigger();
create trigger audit_moveouts after insert or update or delete on public.moveouts
  for each row execute function private.audit_trigger();

-- ---- RLS -------------------------------------------------------------------
alter table public.rent_invoices        enable row level security;
alter table public.rent_payments        enable row level security;
alter table public.reminder_logs        enable row level security;
alter table public.deposit_transactions enable row level security;
alter table public.moveouts             enable row level security;

grant select, insert, update, delete on
  public.rent_invoices, public.rent_payments, public.reminder_logs,
  public.deposit_transactions, public.moveouts
  to authenticated;

-- rent_invoices
create policy "rentinv_select" on public.rent_invoices for select to authenticated
  using (private.has_location_access(location_id));
create policy "rentinv_insert" on public.rent_invoices for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "rentinv_update" on public.rent_invoices for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "rentinv_delete" on public.rent_invoices for delete to authenticated
  using (private.is_super_admin());

-- rent_payments
create policy "rentpay_select" on public.rent_payments for select to authenticated
  using (private.has_location_access(location_id));
create policy "rentpay_insert" on public.rent_payments for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "rentpay_update" on public.rent_payments for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "rentpay_delete" on public.rent_payments for delete to authenticated
  using (private.is_super_admin());

-- reminder_logs
create policy "reminder_select" on public.reminder_logs for select to authenticated
  using (private.has_location_access(location_id));
create policy "reminder_insert" on public.reminder_logs for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "reminder_delete" on public.reminder_logs for delete to authenticated
  using (private.is_super_admin());

-- deposit_transactions
create policy "deposit_select" on public.deposit_transactions for select to authenticated
  using (private.has_location_access(location_id));
create policy "deposit_insert" on public.deposit_transactions for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "deposit_update" on public.deposit_transactions for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "deposit_delete" on public.deposit_transactions for delete to authenticated
  using (private.is_super_admin());

-- moveouts (approval gated by trigger)
create policy "moveout_select" on public.moveouts for select to authenticated
  using (private.has_location_access(location_id));
create policy "moveout_insert" on public.moveouts for insert to authenticated
  with check (private.has_location_access(location_id) and org_id = private.current_org_id());
create policy "moveout_update" on public.moveouts for update to authenticated
  using (private.has_location_access(location_id)) with check (private.has_location_access(location_id));
create policy "moveout_delete" on public.moveouts for delete to authenticated
  using (private.is_super_admin());
