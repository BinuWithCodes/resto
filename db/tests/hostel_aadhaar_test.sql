-- ============================================================================
-- pgTAP — Aadhaar hard rule (§7): only 4 digits may be stored, ever.
-- ============================================================================
begin;
select plan(3);

insert into public.organizations (id, name)
values ('79999999-9999-9999-9999-999999999999', 'Hostel Org');
insert into public.locations (id, org_id, type, name)
values ('7d111111-1111-1111-1111-111111111111','79999999-9999-9999-9999-999999999999','hostel','PG One');

-- 4 digits is accepted
select lives_ok(
  $$ insert into public.tenants (org_id, location_id, name, aadhaar_last4)
     values ('79999999-9999-9999-9999-999999999999','7d111111-1111-1111-1111-111111111111','Valid Tenant','1234') $$,
  'aadhaar_last4 of exactly 4 digits is accepted');

-- a full 12-digit Aadhaar is REJECTED by the CHECK constraint
select throws_ok(
  $$ insert into public.tenants (org_id, location_id, name, aadhaar_last4)
     values ('79999999-9999-9999-9999-999999999999','7d111111-1111-1111-1111-111111111111','Bad Tenant','123456789012') $$,
  '23514', null, 'a full 12-digit Aadhaar is rejected');

-- non-numeric is rejected too
select throws_ok(
  $$ insert into public.tenants (org_id, location_id, name, aadhaar_last4)
     values ('79999999-9999-9999-9999-999999999999','7d111111-1111-1111-1111-111111111111','Bad Tenant 2','12ab') $$,
  '23514', null, 'non-numeric aadhaar_last4 is rejected');

select * from finish();
rollback;
