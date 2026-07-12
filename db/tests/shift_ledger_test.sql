-- ============================================================================
-- pgTAP — Shift ledger: location isolation + lock enforcement (migration 0003)
-- ============================================================================
begin;
select plan(5);

-- ---- Seed as superuser (bypasses RLS) --------------------------------------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','a1111111-1111-1111-1111-111111111111',
   'authenticated','authenticated','shift-a@test.local','', now(), now()),
  ('00000000-0000-0000-0000-000000000000','b2222222-2222-2222-2222-222222222222',
   'authenticated','authenticated','shift-b@test.local','', now(), now());

insert into public.organizations (id, name)
values ('c9999999-9999-9999-9999-999999999999', 'Shift Org');

update public.users set org_id = 'c9999999-9999-9999-9999-999999999999'
where id in ('a1111111-1111-1111-1111-111111111111', 'b2222222-2222-2222-2222-222222222222');

insert into public.locations (id, org_id, type, name) values
  ('d1111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999','restaurant','Resto A'),
  ('d2222222-2222-2222-2222-222222222222','c9999999-9999-9999-9999-999999999999','restaurant','Resto B');

insert into public.memberships (org_id, user_id, location_id, role) values
  ('c9999999-9999-9999-9999-999999999999','a1111111-1111-1111-1111-111111111111','d1111111-1111-1111-1111-111111111111','admin'),
  ('c9999999-9999-9999-9999-999999999999','b2222222-2222-2222-2222-222222222222','d2222222-2222-2222-2222-222222222222','admin');

insert into public.shift_definitions (id, org_id, name, start_time, end_time)
values ('e0000000-0000-0000-0000-000000000000','c9999999-9999-9999-9999-999999999999','Breakfast','06:00','11:00');

insert into public.shift_sessions (id, org_id, location_id, shift_def_id, business_date, opening_cash_paise)
values
  ('f1111111-1111-1111-1111-111111111111','c9999999-9999-9999-9999-999999999999','d1111111-1111-1111-1111-111111111111','e0000000-0000-0000-0000-000000000000','2026-07-12', 500000),
  ('f2222222-2222-2222-2222-222222222222','c9999999-9999-9999-9999-999999999999','d2222222-2222-2222-2222-222222222222','e0000000-0000-0000-0000-000000000000','2026-07-12', 500000);

-- ---- Impersonate admin A (Resto A only) ------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is(
  (select count(*)::int from public.shift_sessions where location_id = 'd2222222-2222-2222-2222-222222222222'),
  0, 'admin A cannot see Resto B shift sessions');
select is(
  (select count(*)::int from public.shift_sessions where location_id = 'd1111111-1111-1111-1111-111111111111'),
  1, 'admin A sees their own Resto A session');

-- income entry into the OPEN session succeeds
insert into public.shift_income_entries (org_id, location_id, session_id, source, mode, amount_paise)
values ('c9999999-9999-9999-9999-999999999999','d1111111-1111-1111-1111-111111111111',
        'f1111111-1111-1111-1111-111111111111','dine_in','cash', 120000);
select is(
  (select count(*)::int from public.shift_income_entries where session_id = 'f1111111-1111-1111-1111-111111111111'),
  1, 'admin A can add income to an open session');

-- admin A locks the session (allowed: was open)
update public.shift_sessions set status = 'locked'
where id = 'f1111111-1111-1111-1111-111111111111';

-- further entries into the LOCKED session are blocked by the trigger
select throws_ok(
  $$ insert into public.shift_income_entries (org_id, location_id, session_id, source, mode, amount_paise)
     values ('c9999999-9999-9999-9999-999999999999','d1111111-1111-1111-1111-111111111111',
             'f1111111-1111-1111-1111-111111111111','parcel','upi', 50000) $$,
  '42501', null, 'locked session rejects new income entries');

-- RLS blocks a non-super_admin from updating a locked session (0 rows changed)
update public.shift_sessions set opening_cash_paise = 999
where id = 'f1111111-1111-1111-1111-111111111111';
select is(
  (select opening_cash_paise from public.shift_sessions where id = 'f1111111-1111-1111-1111-111111111111'),
  500000::bigint, 'admin cannot modify a locked session (RLS)');

reset role;
select * from finish();
rollback;
