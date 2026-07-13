-- ============================================================================
-- pgTAP — post_purchase RPC: transactional write + ledger + idempotent replay
-- (migration 0014). Proves the header/items/movements land together, the total
-- is derived, the balance trigger fires, replay does not double-post, and bad
-- input is rejected.
-- ============================================================================
begin;
select plan(10);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','a1111111-1111-1111-1111-111111111111',
        'authenticated','authenticated','buyer-a@test.local','', now(), now());

insert into public.organizations (id, name) values ('a9999999-9999-9999-9999-999999999999','Buy Org');
update public.users set org_id = 'a9999999-9999-9999-9999-999999999999'
where id = 'a1111111-1111-1111-1111-111111111111';

insert into public.locations (id, org_id, type, name)
values ('ad111111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999','restaurant','Kitchen');
insert into public.memberships (org_id, user_id, location_id, role)
values ('a9999999-9999-9999-9999-999999999999','a1111111-1111-1111-1111-111111111111','ad111111-1111-1111-1111-111111111111','admin');
insert into public.stock_items (id, org_id, name, base_unit, purchase_unit)
values ('ab111111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999','Rice','kg','bag');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- 10 kg @ ₹50/kg (5000 paise) -> line total 50,000 paise; balance 10 kg
create temp table _p1 as select (public.post_purchase(
  'ad111111-1111-1111-1111-111111111111', null, '2026-07-12', 'paid',
  '[{"item_id":"ab111111-1111-1111-1111-111111111111","qty":10,"rate_paise":5000}]'::jsonb,
  null, 'first delivery', 'dev-1', 'key-1'
)).id as pid;

select is(
  (select total_paise from public.purchases where id = (select pid from _p1)),
  50000::bigint, 'purchase total derived from line items');
select is(
  (select line_total_paise from public.purchase_items where purchase_id = (select pid from _p1)),
  50000::bigint, 'line total = round(qty * rate)');
select is(
  (select count(*) from public.stock_movements
   where ref_table='purchases' and ref_id=(select pid from _p1) and movement_type='purchase'),
  1::bigint, 'one purchase movement appended to the ledger');
select is(
  (select qty from public.stock_balances where item_id='ab111111-1111-1111-1111-111111111111'),
  10::numeric, 'balance trigger updated stock to 10 kg');

-- Idempotent replay with the same (device_id, key) returns the same purchase
create temp table _p2 as select (public.post_purchase(
  'ad111111-1111-1111-1111-111111111111', null, '2026-07-12', 'paid',
  '[{"item_id":"ab111111-1111-1111-1111-111111111111","qty":10,"rate_paise":5000}]'::jsonb,
  null, 'first delivery', 'dev-1', 'key-1'
)).id as pid;

select is((select pid from _p2), (select pid from _p1), 'replay returns the stored purchase');
select is(
  (select count(*) from public.purchases), 1::bigint,
  'replay did not create a second purchase');
select is(
  (select qty from public.stock_balances where item_id='ab111111-1111-1111-1111-111111111111'),
  10::numeric, 'replay did not double-post stock');

-- An empty item list is rejected
select throws_ok(
  $$ select public.post_purchase('ad111111-1111-1111-1111-111111111111', null,
       '2026-07-12', 'paid', '[]'::jsonb) $$,
  '22023', null, 'a purchase with no line items is rejected');

-- A line referencing an item outside the org is rejected
select throws_ok(
  $$ select public.post_purchase('ad111111-1111-1111-1111-111111111111', null,
       '2026-07-12', 'paid',
       '[{"item_id":"abffffff-ffff-ffff-ffff-ffffffffffff","qty":1,"rate_paise":100}]'::jsonb) $$,
  'P0002', null, 'a line for an unknown/foreign item is rejected');

-- Posting to a location the caller has no access to is rejected (IDOR guard)
select throws_ok(
  $$ select public.post_purchase('adffffff-ffff-ffff-ffff-ffffffffffff', null,
       '2026-07-12', 'paid',
       '[{"item_id":"ab111111-1111-1111-1111-111111111111","qty":1,"rate_paise":100}]'::jsonb) $$,
  'P0002', null, 'posting to an inaccessible location is rejected');

reset role;
select * from finish();
rollback;
