-- ============================================================================
-- pgTAP — stock posting RPCs (0015): consumption, waste, count finalize.
-- Proves ledger deltas, the negative-stock guard, idempotent replay, waste cost
-- default, and count reconciliation with the draft->posted lock.
-- ============================================================================
begin;
select plan(9);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','b1111111-1111-1111-1111-111111111111',
        'authenticated','authenticated','stock-a@test.local','', now(), now());
insert into public.organizations (id, name) values ('b9999999-9999-9999-9999-999999999999','Stock Org');
update public.users set org_id='b9999999-9999-9999-9999-999999999999' where id='b1111111-1111-1111-1111-111111111111';
insert into public.locations (id, org_id, type, name)
values ('bd111111-1111-1111-1111-111111111111','b9999999-9999-9999-9999-999999999999','restaurant','Kitchen');
insert into public.memberships (org_id, user_id, location_id, role)
values ('b9999999-9999-9999-9999-999999999999','b1111111-1111-1111-1111-111111111111','bd111111-1111-1111-1111-111111111111','admin');
insert into public.stock_items (id, org_id, name, base_unit, purchase_unit, standard_rate_paise)
values ('bb111111-1111-1111-1111-111111111111','b9999999-9999-9999-9999-999999999999','Oil','L','can', 20000);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"b1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- seed 100 L
select public.post_purchase('bd111111-1111-1111-1111-111111111111', null, '2026-07-12','paid',
  '[{"item_id":"bb111111-1111-1111-1111-111111111111","qty":100,"rate_paise":20000}]'::jsonb);

-- consume 30 -> 70
select public.post_consumption('bd111111-1111-1111-1111-111111111111', null,
  '[{"item_id":"bb111111-1111-1111-1111-111111111111","qty":30}]'::jsonb, 'lunch', 'dev-c','ckey-1');
select is(
  (select qty from public.stock_balances where item_id='bb111111-1111-1111-1111-111111111111'),
  70::numeric, 'consumption reduced stock to 70');

-- replay same key -> still 70
select public.post_consumption('bd111111-1111-1111-1111-111111111111', null,
  '[{"item_id":"bb111111-1111-1111-1111-111111111111","qty":30}]'::jsonb, 'lunch', 'dev-c','ckey-1');
select is(
  (select qty from public.stock_balances where item_id='bb111111-1111-1111-1111-111111111111'),
  70::numeric, 'idempotent replay did not double-consume');

-- over-consumption blocked by the negative-stock guard
select throws_ok(
  $$ select public.post_consumption('bd111111-1111-1111-1111-111111111111', null,
       '[{"item_id":"bb111111-1111-1111-1111-111111111111","qty":9999}]'::jsonb) $$,
  '23514', null, 'consuming more than on hand is blocked');

-- waste 5 -> 65, cost defaults to 5 * 20000
select public.post_waste('bd111111-1111-1111-1111-111111111111', null,
  '[{"item_id":"bb111111-1111-1111-1111-111111111111","qty":5,"reason_code":"spoiled"}]'::jsonb, 'dev-w','wkey-1');
select is(
  (select qty from public.stock_balances where item_id='bb111111-1111-1111-1111-111111111111'),
  65::numeric, 'waste reduced stock to 65');
select is(
  (select cost_paise from public.waste_logs where batch_id is not null limit 1),
  100000::bigint, 'waste cost defaulted from standard rate');

-- physical count: counted 60 vs system 65 -> variance -5
insert into public.stock_counts (id, org_id, location_id, count_date)
values ('bc111111-1111-1111-1111-111111111111','b9999999-9999-9999-9999-999999999999',
        'bd111111-1111-1111-1111-111111111111','2026-07-12');
insert into public.stock_count_items (org_id, location_id, count_id, item_id, counted_qty)
values ('b9999999-9999-9999-9999-999999999999','bd111111-1111-1111-1111-111111111111',
        'bc111111-1111-1111-1111-111111111111','bb111111-1111-1111-1111-111111111111', 60);

select is((public.finalize_stock_count('bc111111-1111-1111-1111-111111111111')).status,
  'posted'::public.stock_count_status, 'count finalize flips draft -> posted');
select is(
  (select qty from public.stock_balances where item_id='bb111111-1111-1111-1111-111111111111'),
  60::numeric, 'adjustment movement reconciled stock to the counted 60');
select is(
  (select variance_qty from public.stock_count_items where count_id='bc111111-1111-1111-1111-111111111111'),
  -5::numeric, 'variance recorded as -5 (shrinkage)');

-- re-finalizing a posted count is rejected
select throws_ok(
  $$ select public.finalize_stock_count('bc111111-1111-1111-1111-111111111111') $$,
  'P0001', null, 'a posted count cannot be finalized again');

reset role;
select * from finish();
rollback;
