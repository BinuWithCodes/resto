-- ============================================================================
-- pgTAP — hostel RPCs (0016): rent payment oldest-first allocation + move-out
-- settlement. Proves allocation/status transitions, idempotent replay,
-- overpayment rejection, the super_admin approval gate, and the settle lock.
-- ============================================================================
begin;
select plan(9);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','c1111111-1111-1111-1111-111111111111','authenticated','authenticated','admin-h@test.local','', now(), now()),
 ('00000000-0000-0000-0000-000000000000','c2222222-2222-2222-2222-222222222222','authenticated','authenticated','super-h@test.local','', now(), now());
insert into public.organizations (id, name) values ('c9999999-9999-9999-9999-999999999999','Hostel Org');
update public.users set org_id='c9999999-9999-9999-9999-999999999999'
  where id in ('c1111111-1111-1111-1111-111111111111','c2222222-2222-2222-2222-222222222222');
insert into public.locations (id, org_id, type, name)
values ('cd111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999','hostel','PG-1');
insert into public.memberships (org_id, user_id, location_id, role) values
 ('c9999999-9999-9999-9999-999999999999','c1111111-1111-1111-1111-111111111111','cd111111-1111-1111-1111-111111111111','admin'),
 ('c9999999-9999-9999-9999-999999999999','c2222222-2222-2222-2222-222222222222', null, 'super_admin');
insert into public.tenants (id, org_id, location_id, name, rent_paise, deposit_paise)
values ('ce111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999',
        'cd111111-1111-1111-1111-111111111111','Ravi', 10000, 20000);
insert into public.rent_invoices (id, org_id, location_id, tenant_id, period, due_date, base_rent_paise, total_paise, status) values
 ('cf111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999','cd111111-1111-1111-1111-111111111111','ce111111-1111-1111-1111-111111111111','2026-07','2026-07-05',10000,10000,'due'),
 ('cf222222-2222-2222-2222-222222222222','c9999999-9999-9999-9999-999999999999','cd111111-1111-1111-1111-111111111111','ce111111-1111-1111-1111-111111111111','2026-08','2026-08-05',10000,10000,'due');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- pay 15000 -> July paid, Aug partial (oldest-first)
select public.record_rent_payment('ce111111-1111-1111-1111-111111111111', 15000, '2026-07-06','upi','dev-r','rkey-1');
select is((select status from public.rent_invoices where id='cf111111-1111-1111-1111-111111111111'),
  'paid'::public.rent_invoice_status, 'oldest invoice fully cleared first');
select is((select status from public.rent_invoices where id='cf222222-2222-2222-2222-222222222222'),
  'partial'::public.rent_invoice_status, 'later invoice left partial');

-- idempotent replay
select public.record_rent_payment('ce111111-1111-1111-1111-111111111111', 15000, '2026-07-06','upi','dev-r','rkey-1');
select is((select count(*) from public.rent_payments), 2::bigint,
  'idempotent replay did not add payment rows');

-- overpayment beyond outstanding rejected
select throws_ok(
  $$ select public.record_rent_payment('ce111111-1111-1111-1111-111111111111', 6000, '2026-07-07','cash') $$,
  'P0001', null, 'overpayment beyond open invoices is rejected');

-- exact remaining clears Aug
select public.record_rent_payment('ce111111-1111-1111-1111-111111111111', 5000, '2026-07-08','cash');
select is((select status from public.rent_invoices where id='cf222222-2222-2222-2222-222222222222'),
  'paid'::public.rent_invoice_status, 'exact remaining clears the invoice');

reset role;
insert into public.deposit_transactions (org_id, location_id, tenant_id, type, amount_paise, description)
values ('c9999999-9999-9999-9999-999999999999','cd111111-1111-1111-1111-111111111111','ce111111-1111-1111-1111-111111111111','received',20000,'join deposit');
insert into public.moveouts (id, org_id, location_id, tenant_id, notice_date, vacate_date, dues_paise, damages_paise)
values ('c0111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999','cd111111-1111-1111-1111-111111111111','ce111111-1111-1111-1111-111111111111','2026-07-01','2026-07-31',3000,2000);

-- admin cannot settle
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select throws_ok(
  $$ select public.settle_moveout('c0111111-1111-1111-1111-111111111111') $$,
  '42501', null, 'admin cannot approve a move-out settlement');

-- super_admin settles: refund = 20000 - 2000 - 3000 = 15000
select set_config('request.jwt.claims',
  '{"sub":"c2222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((public.settle_moveout('c0111111-1111-1111-1111-111111111111')).refund_paise,
  15000::bigint, 'refund = deposit - damages - dues');
select is((select status from public.tenants where id='ce111111-1111-1111-1111-111111111111'),
  'vacated'::public.tenant_status, 'settlement marks the tenant vacated');
select throws_ok(
  $$ select public.settle_moveout('c0111111-1111-1111-1111-111111111111') $$,
  'P0001', null, 'a settled move-out cannot be settled again');

reset role;
select * from finish();
rollback;
