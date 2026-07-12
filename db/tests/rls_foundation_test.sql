-- ============================================================================
-- pgTAP — Foundation RLS & write-lock invariants (migration 0001)
-- Run by `supabase test db`. Self-contained: catalog + privilege assertions,
-- no seeded auth users (behavioral cross-location isolation tests are added
-- next, once this harness is confirmed green in CI).
-- ============================================================================
begin;
select plan(17);

-- ── The prime directive: RLS on EVERY public base table (catches new tables) ─
select is(
  (select count(*)::int
     from pg_tables t
     join pg_class c
       on c.relname = t.tablename
      and c.relnamespace = 'public'::regnamespace
    where t.schemaname = 'public'
      and c.relkind = 'r'
      and not c.relrowsecurity),
  0,
  'every public base table has RLS enabled'
);

-- ── All 7 foundation tables exist ────────────────────────────────────────────
select is(
  (select count(*)::int
     from pg_tables
    where schemaname = 'public'
      and tablename in (
        'organizations','locations','users','memberships',
        'audit_logs','system_metrics','notifications_log'
      )),
  7,
  'all 7 identity/system tables exist'
);

-- ── Per-table policy presence ────────────────────────────────────────────────
select cmp_ok(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='organizations'),
  '>=', 2, 'organizations has >= 2 policies');
select cmp_ok(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='locations'),
  '>=', 4, 'locations has SELECT/INSERT/UPDATE/DELETE policies');
select cmp_ok(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='users'),
  '>=', 2, 'users has >= 2 policies');
select cmp_ok(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='memberships'),
  '>=', 4, 'memberships has SELECT/INSERT/UPDATE/DELETE policies');
select is(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='audit_logs'),
  1, 'audit_logs has exactly one policy (SELECT only)');
select is(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='system_metrics'),
  1, 'system_metrics has exactly one policy (SELECT only)');
select is(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='notifications_log'),
  2, 'notifications_log has SELECT + INSERT policies');

-- ── Security-definer helpers live in `private` and are SECURITY DEFINER ───────
select ok(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='has_location_access'),
  'private.has_location_access is SECURITY DEFINER');
select ok(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='is_super_admin'),
  'private.is_super_admin is SECURITY DEFINER');
select ok(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='current_org_id'),
  'private.current_org_id is SECURITY DEFINER');

-- ── audit_logs is write-locked for authenticated (grants revoked, §4.4) ──────
select ok(not has_table_privilege('authenticated','public.audit_logs','INSERT'),
  'authenticated cannot INSERT audit_logs');
select ok(not has_table_privilege('authenticated','public.audit_logs','UPDATE'),
  'authenticated cannot UPDATE audit_logs');
select ok(not has_table_privilege('authenticated','public.audit_logs','DELETE'),
  'authenticated cannot DELETE audit_logs');

-- ── system_metrics write path is service_role-only ───────────────────────────
select ok(not has_table_privilege('authenticated','public.system_metrics','INSERT'),
  'authenticated cannot INSERT system_metrics');

-- ── `private` schema is not reachable by authenticated (usage revoked) ───────
select ok(not has_schema_privilege('authenticated','private','USAGE'),
  'authenticated has no USAGE on private schema');

select * from finish();
rollback;
