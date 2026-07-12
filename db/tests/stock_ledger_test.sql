-- ============================================================================
-- pgTAP — Stock ledger: balance maintenance + negative-stock guard (0005)
-- ============================================================================
begin;
select plan(5);

-- ---- Seed as superuser -----------------------------------------------------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','51111111-1111-1111-1111-111111111111',
        'authenticated','authenticated','stock-a@test.local','', now(), now());

insert into public.organizations (id, name)
values ('59999999-9999-9999-9999-999999999999', 'Stock Org');

update public.users set org_id = '59999999-9999-9999-9999-999999999999'
where id = '51111111-1111-1111-1111-111111111111';

insert into public.locations (id, org_id, type, name)
values ('5d111111-1111-1111-1111-111111111111','59999999-9999-9999-9999-999999999999','restaurant','Kitchen');

insert into public.memberships (org_id, user_id, location_id, role)
values ('59999999-9999-9999-9999-999999999999','51111111-1111-1111-1111-111111111111',
        '5d111111-1111-1111-1111-111111111111','admin');

insert into public.stock_items (id, org_id, name, base_unit, purchase_unit)
values ('5a111111-1111-1111-1111-111111111111','59999999-9999-9999-9999-999999999999','Rice','kg','bag');

-- ---- Impersonate the admin -------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"51111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- purchase +100 kg
insert into public.stock_movements (org_id, location_id, item_id, movement_type, qty_delta, rate_paise)
values ('59999999-9999-9999-9999-999999999999','5d111111-1111-1111-1111-111111111111',
        '5a111111-1111-1111-1111-111111111111','purchase', 100, 4000);
select is(
  (select qty from public.stock_balances
    where location_id='5d111111-1111-1111-1111-111111111111' and item_id='5a111111-1111-1111-1111-111111111111'),
  100::numeric(12,3), 'purchase raises the cached balance to 100');

-- consume 40 kg
insert into public.stock_movements (org_id, location_id, item_id, movement_type, qty_delta)
values ('59999999-9999-9999-9999-999999999999','5d111111-1111-1111-1111-111111111111',
        '5a111111-1111-1111-1111-111111111111','consumption', -40);
select is(
  (select qty from public.stock_balances
    where location_id='5d111111-1111-1111-1111-111111111111' and item_id='5a111111-1111-1111-1111-111111111111'),
  60::numeric(12,3), 'consumption lowers the balance to 60');

-- consuming more than on hand is blocked by the negative-stock guard
select throws_ok(
  $$ insert into public.stock_movements (org_id, location_id, item_id, movement_type, qty_delta)
     values ('59999999-9999-9999-9999-999999999999','5d111111-1111-1111-1111-111111111111',
             '5a111111-1111-1111-1111-111111111111','consumption', -100) $$,
  '23514', null, 'negative-stock guard blocks over-consumption');

select is(
  (select qty from public.stock_balances
    where location_id='5d111111-1111-1111-1111-111111111111' and item_id='5a111111-1111-1111-1111-111111111111'),
  60::numeric(12,3), 'balance is unchanged after the blocked movement');

-- movements are append-only: no UPDATE privilege for authenticated
select ok(not has_table_privilege('authenticated','public.stock_movements','UPDATE'),
  'stock_movements is append-only (no UPDATE grant)');

reset role;
select * from finish();
rollback;
