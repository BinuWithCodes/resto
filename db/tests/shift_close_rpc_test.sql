-- ============================================================================
-- pgTAP — close_shift / lock_shift RPC: reconciliation, variance, lock (0013)
-- ============================================================================
begin;
select plan(6);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','c1111111-1111-1111-1111-111111111111',
        'authenticated','authenticated','close-a@test.local','', now(), now());

insert into public.organizations (id, name) values ('c9999999-9999-9999-9999-999999999999','Close Org');
update public.users set org_id = 'c9999999-9999-9999-9999-999999999999'
where id = 'c1111111-1111-1111-1111-111111111111';

insert into public.locations (id, org_id, type, name)
values ('cd111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999','restaurant','Cafe');
insert into public.memberships (org_id, user_id, location_id, role)
values ('c9999999-9999-9999-9999-999999999999','c1111111-1111-1111-1111-111111111111','cd111111-1111-1111-1111-111111111111','admin');
insert into public.shift_definitions (id, org_id, name, start_time, end_time)
values ('ce111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999','Lunch','11:00','16:00');

-- open session with ₹5,000 opening cash
insert into public.shift_sessions (id, org_id, location_id, shift_def_id, business_date, opening_cash_paise)
values ('cf111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999',
        'cd111111-1111-1111-1111-111111111111','ce111111-1111-1111-1111-111111111111','2026-07-12', 500000);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- ₹3,000 cash income + ₹1,000 cash expense -> expected closing = 5000+3000-1000 = 7000
insert into public.shift_income_entries (org_id, location_id, session_id, source, mode, amount_paise)
values ('c9999999-9999-9999-9999-999999999999','cd111111-1111-1111-1111-111111111111',
        'cf111111-1111-1111-1111-111111111111','dine_in','cash', 300000);
insert into public.shift_expense_entries (org_id, location_id, session_id, amount_paise, mode)
values ('c9999999-9999-9999-9999-999999999999','cd111111-1111-1111-1111-111111111111',
        'cf111111-1111-1111-1111-111111111111', 100000, 'cash');

-- closing with a mismatch and no reason is rejected
select throws_ok(
  $$ select public.close_shift('cf111111-1111-1111-1111-111111111111', 690000, null, null) $$,
  'P0001', null, 'variance without a reason is rejected');

-- close with exact cash (₹7,000) -> variance 0, status closed
select is(
  (public.close_shift('cf111111-1111-1111-1111-111111111111', 700000, null, 'handover ok')).variance_paise,
  0::bigint, 'exact cash reconciles to zero variance');
select is(
  (select status from public.shift_sessions where id='cf111111-1111-1111-1111-111111111111'),
  'closed'::public.shift_status, 'session is now closed');
select is(
  (select expected_closing_cash_paise from public.shift_sessions where id='cf111111-1111-1111-1111-111111111111'),
  700000::bigint, 'expected closing cash computed from entries');

-- closing an already-closed shift fails
select throws_ok(
  $$ select public.close_shift('cf111111-1111-1111-1111-111111111111', 700000, null, null) $$,
  'P0001', null, 'cannot close a shift that is not open');

-- lock the closed shift
select is(
  (public.lock_shift('cf111111-1111-1111-1111-111111111111')).status,
  'locked'::public.shift_status, 'closed shift can be locked');

reset role;
select * from finish();
rollback;
