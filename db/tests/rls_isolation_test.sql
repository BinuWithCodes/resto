-- ============================================================================
-- pgTAP — Behavioral RLS proof: cross-location isolation + audit immutability
-- Seeds two admins scoped to two hostels, impersonates admin A via JWT claims,
-- and proves admin A cannot see hostel B's rows (§8 flagship requirement).
-- ============================================================================
begin;
select plan(4);

-- ── Seed as superuser (bypasses RLS) ─────────────────────────────────────────
-- auth.users inserts fire on_auth_user_created -> public.users mirror rows.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111',
   'authenticated','authenticated','admin-a@test.local','', now(), now()),
  ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222',
   'authenticated','authenticated','admin-b@test.local','', now(), now());

insert into public.organizations (id, name)
values ('99999999-9999-9999-9999-999999999999', 'Test Org');

-- mirror rows were created before the org existed; attach org now
update public.users set org_id = '99999999-9999-9999-9999-999999999999'
where id in ('11111111-1111-1111-1111-111111111111',
             '22222222-2222-2222-2222-222222222222');

insert into public.locations (id, org_id, type, name) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','99999999-9999-9999-9999-999999999999','hostel','Hostel A'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','99999999-9999-9999-9999-999999999999','hostel','Hostel B');

insert into public.memberships (org_id, user_id, location_id, role) values
  ('99999999-9999-9999-9999-999999999999','11111111-1111-1111-1111-111111111111',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','admin'),
  ('99999999-9999-9999-9999-999999999999','22222222-2222-2222-2222-222222222222',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','admin');

-- ── Impersonate admin A (location A only) ────────────────────────────────────
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',
  true
);

select is(
  (select count(*)::int from public.locations
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  0, 'admin A cannot see Hostel B (cross-location isolation)');

select is(
  (select count(*)::int from public.locations
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1, 'admin A can see their own Hostel A');

-- audit_logs is append-only: authenticated has no UPDATE grant -> permission denied
select throws_ok(
  $$ update public.audit_logs set action = 'TAMPER' $$,
  '42501',
  null,
  'authenticated cannot UPDATE audit_logs (append-only)');

reset role;

-- ── Back as superuser: the audit trigger recorded the config-table inserts ────
select cmp_ok(
  (select count(*)::int from public.audit_logs),
  '>=', 4, 'audit trigger logged location + membership inserts');

select * from finish();
rollback;
