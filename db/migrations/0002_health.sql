-- ============================================================================
-- Migration 0002 — health check function
-- A trivial `select 1` reachable by the anon role so /api/health can verify DB
-- reachability with a single cheap round-trip (no table read -> negligible
-- egress, per the free-tier budget). Touches no tables, so no RLS concern.
-- ============================================================================
create or replace function public.health()
returns integer language sql stable as $$ select 1 $$;

grant execute on function public.health() to anon, authenticated;
