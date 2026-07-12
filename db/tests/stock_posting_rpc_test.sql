-- ============================================================================
-- pgTAP — stock-posting RPCs: post_purchase / post_consumption / post_waste
-- Covers: source row + movement written together, balance maintenance,
-- idempotent replay (no double-post), negative-stock guard, cross-location
-- isolation. (migration 0014)
-- ============================================================================
begin;
select plan(13);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','a1111111-1111-1111-1111-111111111111',
        'authenticated','authenticated','stockpost-a@test.local','', now(), now());

insert into public.organizations (id, name) values ('a9999999-9999-9999-9999-999999999999','Stock Org');
update public.users set org_id = 'a9999999-9999-9999-9999-999999999999'
where id = 'a1111111-1111-1111-1111-111111111111';

-- location A (admin has access) and B (no access)
insert into public.locations (id, org_id, type, name) values
  ('ada11111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999','restaurant','Cafe A'),
  ('adb11111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999','restaurant','Cafe B');
insert into public.memberships (org_id, user_id, location_id, role)
values ('a9999999-9999-9999-9999-999999999999','a1111111-1111-1111-1111-111111111111',
        'ada11111-1111-1111-1111-111111111111','admin');

-- item: purchase unit "bag" = 25 kg (base), standard rate ₹50.00/kg = 5000 paise
insert into public.stock_items
  (id, org_id, name, base_unit, purchase_unit, conversion_factor, standard_rate_paise)
values ('a1e11111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999',
        'Rice','kg','bag',25,5000);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- ---- post_purchase: 2 bags @ ₹1000/bag -> total 200000; base qty 50 kg -------
select is(
  (public.post_purchase('dev-1','aaaa0001-0000-0000-0000-000000000001',
     'ada11111-1111-1111-1111-111111111111', null, '2026-07-12', 'paid', null, null,
     '[{"item_id":"a1e11111-1111-1111-1111-111111111111","qty":2,"rate_paise":100000}]'::jsonb
   )->>'total_paise')::bigint,
  200000::bigint, 'purchase total is sum of line totals');

select is(
  (select qty from public.stock_balances where item_id='a1e11111-1111-1111-1111-111111111111'),
  50::numeric(12,3), 'purchase adds base-unit qty (2 bags x 25 = 50 kg)');

select is((select count(*) from public.purchases)::int, 1, 'one purchase row created');

-- ---- replay: same (device_id, key) returns stored result, posts nothing -----
select is(
  (public.post_purchase('dev-1','aaaa0001-0000-0000-0000-000000000001',
     'ada11111-1111-1111-1111-111111111111', null, '2026-07-12', 'paid', null, null,
     '[{"item_id":"a1e11111-1111-1111-1111-111111111111","qty":2,"rate_paise":100000}]'::jsonb
   )->>'total_paise')::bigint,
  200000::bigint, 'replay returns the stored result');

select is((select count(*) from public.purchases)::int, 1, 'replay does not create a second purchase');
select is(
  (select qty from public.stock_balances where item_id='a1e11111-1111-1111-1111-111111111111'),
  50::numeric(12,3), 'replay does not move stock again');

-- ---- post_consumption: 10 kg -> value 50000; balance 40 ---------------------
select is(
  (public.post_consumption('dev-1','bbbb0001-0000-0000-0000-000000000001',
     'ada11111-1111-1111-1111-111111111111', null, 'lunch prep',
     '[{"item_id":"a1e11111-1111-1111-1111-111111111111","qty":10}]'::jsonb
   )->>'value_paise')::bigint,
  50000::bigint, 'consumption valued at standard rate (10 x 5000)');

select is(
  (select qty from public.stock_balances where item_id='a1e11111-1111-1111-1111-111111111111'),
  40::numeric(12,3), 'consumption reduces balance');

-- ---- negative-stock guard rejects an overdraw; balance unchanged ------------
select throws_ok(
  $$ select public.post_consumption('dev-1','bbbb0001-0000-0000-0000-000000000002',
       'ada11111-1111-1111-1111-111111111111', null, null,
       '[{"item_id":"a1e11111-1111-1111-1111-111111111111","qty":1000}]'::jsonb) $$,
  '23514', null, 'overdrawing stock is rejected');

select is(
  (select qty from public.stock_balances where item_id='a1e11111-1111-1111-1111-111111111111'),
  40::numeric(12,3), 'rejected overdraw leaves balance untouched');

-- ---- post_waste: 5 kg -> cost 25000; balance 35 ----------------------------
select is(
  (public.post_waste('dev-1','cccc0001-0000-0000-0000-000000000001',
     'ada11111-1111-1111-1111-111111111111','a1e11111-1111-1111-1111-111111111111',
     5,'spoiled', null, null, 'fridge failure')->>'cost_paise')::bigint,
  25000::bigint, 'waste cost defaults to qty x standard rate');

select is(
  (select qty from public.stock_balances where item_id='a1e11111-1111-1111-1111-111111111111'),
  35::numeric(12,3), 'waste reduces balance');

-- ---- cross-location isolation: cannot post at a location without access ------
select throws_ok(
  $$ select public.post_purchase('dev-1','dddd0001-0000-0000-0000-000000000001',
       'adb11111-1111-1111-1111-111111111111', null, '2026-07-12', 'paid', null, null,
       '[{"item_id":"a1e11111-1111-1111-1111-111111111111","qty":1,"rate_paise":100000}]'::jsonb) $$,
  '42501', null, 'admin cannot post a purchase at a location they cannot access');

reset role;
select * from finish();
rollback;
