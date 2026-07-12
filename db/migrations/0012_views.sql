-- ============================================================================
-- Migration 0012 — Derived aggregates (Phase 4). Views, not stored numbers
-- (§5: never store what can be derived). All use security_invoker so the base
-- tables' RLS applies to the caller — an admin sees only their locations.
-- ============================================================================

-- ---- daily_summaries: restaurant income/expense/net per location per date --
create view public.daily_summaries
with (security_invoker = true) as
with inc as (
  select session_id, sum(amount_paise) as amt
  from public.shift_income_entries group by session_id
),
exp as (
  select session_id, sum(amount_paise) as amt
  from public.shift_expense_entries group by session_id
)
select
  s.org_id,
  s.location_id,
  s.business_date,
  coalesce(sum(inc.amt), 0) as income_paise,
  coalesce(sum(exp.amt), 0) as expense_paise,
  coalesce(sum(inc.amt), 0) - coalesce(sum(exp.amt), 0) as net_paise
from public.shift_sessions s
left join inc on inc.session_id = s.id
left join exp on exp.session_id = s.id
group by s.org_id, s.location_id, s.business_date;

-- ---- stock_valuation_view: current stock value at standard rate -------------
create view public.stock_valuation_view
with (security_invoker = true) as
select
  b.org_id,
  b.location_id,
  b.item_id,
  b.qty,
  i.standard_rate_paise,
  round(b.qty * i.standard_rate_paise) as value_paise
from public.stock_balances b
join public.stock_items i on i.id = b.item_id;

-- ---- collection_efficiency_view: rent invoiced vs collected per period ------
create view public.collection_efficiency_view
with (security_invoker = true) as
with paid as (
  select invoice_id, sum(amount_paise) as amt
  from public.rent_payments
  where not reversed
  group by invoice_id
)
select
  ri.org_id,
  ri.location_id,
  ri.period,
  sum(ri.total_paise) as invoiced_paise,
  coalesce(sum(paid.amt), 0) as collected_paise
from public.rent_invoices ri
left join paid on paid.invoice_id = ri.id
group by ri.org_id, ri.location_id, ri.period;

grant select on
  public.daily_summaries, public.stock_valuation_view, public.collection_efficiency_view
  to authenticated;
