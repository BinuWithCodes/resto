-- ============================================================================
-- pgTAP — payroll RPCs (0017): run_payroll + approve_payroll. Proves net math
-- (salary − unpaid leave − advance instalment), advance_deduction recording,
-- duplicate-run rejection, the super_admin approval gate, and attendance lock.
-- ============================================================================
begin;
select plan(8);

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','d1111111-1111-1111-1111-111111111111','authenticated','authenticated','admin-p@test.local','', now(), now()),
 ('00000000-0000-0000-0000-000000000000','d2222222-2222-2222-2222-222222222222','authenticated','authenticated','super-p@test.local','', now(), now());
insert into public.organizations (id, name) values ('d9999999-9999-9999-9999-999999999999','Payroll Org');
update public.users set org_id='d9999999-9999-9999-9999-999999999999'
  where id in ('d1111111-1111-1111-1111-111111111111','d2222222-2222-2222-2222-222222222222');
insert into public.locations (id, org_id, type, name)
values ('dd111111-1111-1111-1111-111111111111','d9999999-9999-9999-9999-999999999999','restaurant','Cafe');
insert into public.memberships (org_id, user_id, location_id, role) values
 ('d9999999-9999-9999-9999-999999999999','d1111111-1111-1111-1111-111111111111','dd111111-1111-1111-1111-111111111111','admin'),
 ('d9999999-9999-9999-9999-999999999999','d2222222-2222-2222-2222-222222222222', null, 'super_admin');
insert into public.employees (id, org_id, name, monthly_salary_paise, status) values
 ('de111111-1111-1111-1111-111111111111','d9999999-9999-9999-9999-999999999999','Asha', 26000,'active'),
 ('de222222-2222-2222-2222-222222222222','d9999999-9999-9999-9999-999999999999','Bala', 30000,'active');
insert into public.leaves (org_id, employee_id, from_date, to_date, days, status, unpaid)
values ('d9999999-9999-9999-9999-999999999999','de111111-1111-1111-1111-111111111111','2026-07-10','2026-07-11',2,'approved',true);
insert into public.advances (id, org_id, employee_id, amount_paise, instalments, status)
values ('da111111-1111-1111-1111-111111111111','d9999999-9999-9999-9999-999999999999','de111111-1111-1111-1111-111111111111',6000,3,'approved');
insert into public.attendance (org_id, location_id, employee_id, att_date, status)
values ('d9999999-9999-9999-9999-999999999999','dd111111-1111-1111-1111-111111111111','de111111-1111-1111-1111-111111111111','2026-07-15','present');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d1111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- run payroll (per_day 26000/26=1000; leave 2*1000=2000; advance 6000/3=2000)
create temp table _run as select (public.run_payroll('2026-07', 26)).id as rid;

select is((select net_paise from public.payroll_items where employee_id='de111111-1111-1111-1111-111111111111'),
  22000::bigint, 'E1 net = 26000 - 2000 leave - 2000 advance');
select is((select advance_deduction_paise from public.payroll_items where employee_id='de111111-1111-1111-1111-111111111111'),
  2000::bigint, 'E1 advance instalment deducted');
select is((select net_paise from public.payroll_items where employee_id='de222222-2222-2222-2222-222222222222'),
  30000::bigint, 'E2 net = full salary (no leave/advance)');
select is((select count(*) from public.advance_deductions), 1::bigint,
  'one advance_deduction row recorded');

-- duplicate run rejected
select throws_ok(
  $$ select public.run_payroll('2026-07', 26) $$,
  'P0001', null, 'a second run for the same period is rejected');

-- admin cannot approve
select throws_ok(
  $$ select public.approve_payroll((select rid from _run)) $$,
  '42501', null, 'admin cannot approve payroll');

-- super_admin approves, attendance locks
select set_config('request.jwt.claims',
  '{"sub":"d2222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((public.approve_payroll((select rid from _run))).status,
  'approved'::public.payroll_status, 'super_admin approval flips run to approved');
select is(
  (select locked from public.attendance where employee_id='de111111-1111-1111-1111-111111111111' and att_date='2026-07-15'),
  true, 'approval locks the period''s attendance');

reset role;
select * from finish();
rollback;
