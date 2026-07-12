-- ============================================================================
-- pgTAP — Payroll approval + attendance lock are super_admin-gated (0010, 0011)
-- ============================================================================
begin;
select plan(3);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000','a0111111-1111-1111-1111-111111111111',
   'authenticated','authenticated','pay-admin@test.local','', now(), now()),
  ('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','pay-owner@test.local','', now(), now());

insert into public.organizations (id, name) values ('a9999999-9999-9999-9999-999999999999','Pay Org');
update public.users set org_id = 'a9999999-9999-9999-9999-999999999999'
where id in ('a0111111-1111-1111-1111-111111111111','a0000000-0000-0000-0000-000000000000');

insert into public.locations (id, org_id, type, name)
values ('ad111111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999','restaurant','Main');

insert into public.memberships (org_id, user_id, location_id, role) values
  ('a9999999-9999-9999-9999-999999999999','a0111111-1111-1111-1111-111111111111','ad111111-1111-1111-1111-111111111111','admin'),
  ('a9999999-9999-9999-9999-999999999999','a0000000-0000-0000-0000-000000000000', null, 'super_admin');

insert into public.employees (id, org_id, name, monthly_salary_paise)
values ('ae111111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999','Cook', 3000000);

insert into public.payroll_runs (id, org_id, period, status)
values ('af111111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999','2026-07','draft');

insert into public.attendance (id, org_id, location_id, employee_id, att_date, status, locked)
values ('ac111111-1111-1111-1111-111111111111','a9999999-9999-9999-9999-999999999999',
        'ad111111-1111-1111-1111-111111111111','ae111111-1111-1111-1111-111111111111','2026-07-01','present', true);

-- admin cannot approve payroll
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a0111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select throws_ok(
  $$ update public.payroll_runs set status='approved' where id='af111111-1111-1111-1111-111111111111' $$,
  '42501', null, 'an admin cannot approve payroll');
-- admin cannot edit locked attendance
select throws_ok(
  $$ update public.attendance set status='absent' where id='ac111111-1111-1111-1111-111111111111' $$,
  '42501', null, 'locked attendance rejects admin edits');
reset role;

-- super_admin can approve payroll
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
select lives_ok(
  $$ update public.payroll_runs set status='approved', approved_by='a0000000-0000-0000-0000-000000000000'
     where id='af111111-1111-1111-1111-111111111111' $$,
  'a super_admin can approve payroll');
reset role;

select * from finish();
rollback;
