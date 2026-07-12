-- ============================================================================
-- pgTAP — Move-out settlement approval is super_admin-only (§1.1, migration 0008)
-- ============================================================================
begin;
select plan(2);

-- ---- Seed: one admin (location-scoped) and one super_admin (org-wide) ------
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','81111111-1111-1111-1111-111111111111',
   'authenticated','authenticated','mo-admin@test.local','', now(), now()),
  ('00000000-0000-0000-0000-000000000000','80000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','mo-owner@test.local','', now(), now());

insert into public.organizations (id, name)
values ('89999999-9999-9999-9999-999999999999', 'MO Org');

update public.users set org_id = '89999999-9999-9999-9999-999999999999'
where id in ('81111111-1111-1111-1111-111111111111', '80000000-0000-0000-0000-000000000000');

insert into public.locations (id, org_id, type, name)
values ('8d111111-1111-1111-1111-111111111111','89999999-9999-9999-9999-999999999999','hostel','PG');

insert into public.memberships (org_id, user_id, location_id, role) values
  ('89999999-9999-9999-9999-999999999999','81111111-1111-1111-1111-111111111111','8d111111-1111-1111-1111-111111111111','admin'),
  ('89999999-9999-9999-9999-999999999999','80000000-0000-0000-0000-000000000000', null, 'super_admin');

insert into public.tenants (id, org_id, location_id, name)
values ('8a111111-1111-1111-1111-111111111111','89999999-9999-9999-9999-999999999999','8d111111-1111-1111-1111-111111111111','Leaver');

insert into public.moveouts (id, org_id, location_id, tenant_id, status)
values ('8b111111-1111-1111-1111-111111111111','89999999-9999-9999-9999-999999999999','8d111111-1111-1111-1111-111111111111','8a111111-1111-1111-1111-111111111111','pending');

-- ---- admin cannot approve --------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"81111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select throws_ok(
  $$ update public.moveouts set status = 'approved'
     where id = '8b111111-1111-1111-1111-111111111111' $$,
  '42501', null, 'an admin cannot approve a move-out settlement');
reset role;

-- ---- super_admin can approve -----------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"80000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select lives_ok(
  $$ update public.moveouts set status = 'approved', approved_by = '80000000-0000-0000-0000-000000000000'
     where id = '8b111111-1111-1111-1111-111111111111' $$,
  'a super_admin can approve a move-out settlement');
reset role;

select * from finish();
rollback;
