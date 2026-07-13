# Build Status

Living snapshot of what's built, verified, and remaining. Update as work lands.
Branch: `claude/claude-md-kickoff-c345zi` → PRs into `main`.

## Verified in CI (build + lint + typecheck + Vitest + pgTAP all green)

### Phase 0 — Foundation
- Next.js 16 + TS strict + Tailwind v4 + shadcn foundation; `§4.6` directory layout
- GitHub Actions CI: `build` job (typecheck/lint/format/test/build) + `db` job
  (`supabase db start` + `supabase test db`), ≤10 min, concurrency-cancel
- **Migration 0001** — identity/system: organizations, locations, users,
  memberships, audit_logs, system_metrics, notifications_log. RLS + policies +
  indexes; `private` security-definer helpers (has_location_access,
  is_super_admin, current_org_id) reading `memberships`; audit trigger;
  auth.users→users mirror
- **Migration 0002** — `health()` (`select 1`) for /api/health
- `authedAction()` wrapper (AUTHORIZE→VALIDATE→MUTATE, IDOR guard) + 8 tests
- Supabase clients (browser/server/service), env accessor, rate-limit +
  observability seams
- Bilingual i18n (en/ta, cookie locale, Server Action switcher) + responsive
  app shell + `design-system/MASTER.md`
- Ops: `/api/health`, keep-alive cron, nightly pg_dump→R2 backup workflow, RUNBOOK
- **pgTAP:** RLS-on-every-table, cross-location isolation, audit_logs immutability

### Phase 1 — Restaurant
- **lib/money.ts** (19 tests), **lib/stock.ts** (8 tests), **lib/dates.ts** (8 tests)
- **0003** shift ledger (definitions, sessions, income, expense_categories,
  expense) — shift lock enforced in RLS + trigger (pgTAP-proven)
- **0004** stock master (categories, suppliers, items) + supplier FK
- **0005** append-only stock_movements + trigger-maintained stock_balances +
  negative-stock guard (pgTAP-proven)
- **0006** purchases, purchase_items, supplier_payments, waste_logs,
  stock_counts, stock_count_items, consumption_templates (+ items)

### Phase 2 — Hostel
- **0007** rooms, beds, tenants (Aadhaar-last-4 CHECK, pgTAP-proven), bed_assignments
- **0008** rent_invoices, rent_payments, reminder_logs, deposit_transactions,
  moveouts (super_admin approval, pgTAP-proven)
- **0009** utility_bills/splits, meal_plans, meal_subscriptions, meal_skips

### Phase 3 — Staff
- **0010** employees, roster_entries, attendance (post-payroll lock, pgTAP-proven)
- **0011** leave_types/balances/leaves, advances (+ deductions), payroll_runs +
  payroll_items — payroll/advance approval + payroll lock super_admin-gated
  (pgTAP-proven)

### Phase 4 — Analytics
- **0012** views: daily_summaries, stock_valuation_view,
  collection_efficiency_view (security_invoker; RLS flows through)

### Transactional RPCs (§4.4)
- **0013** `close_shift` (cash reconcile + mandatory variance reason) + `lock_shift`
  — SECURITY INVOKER, RLS-scoped; open→closed→locked (pgTAP-proven)
- **0014** `post_purchase` — writes purchase header + items + append-only
  stock_movements in one transaction; total derived; balance trigger fires;
  org derived from the location row (RLS gate, no direct `private` calls);
  reusable `idempotency_keys` table (UNIQUE(device_id, key)) makes offline-synced
  replays safe (pgTAP-proven: reconcile, replay-no-double-post, empty/foreign
  item + inaccessible-location rejection)
- **0015** `post_consumption`, `post_waste`, `finalize_stock_count` — batch-
  idempotent negative-guarded ledger writes; count posting reconciles balances
  and locks draft→posted (pgTAP-proven)
- **0016** `record_rent_payment` (oldest-first allocation, overpayment rejected,
  batch-idempotent) + `settle_moveout` (deposit refund, super_admin-gated,
  settle-once) (pgTAP-proven)
- **0017** `run_payroll` (net = salary − unpaid leave − advance instalment;
  advance_deductions recorded; duplicate-run rejected) + `approve_payroll`
  (super_admin-gated, locks the period's attendance) (pgTAP-proven)

### App layer (Server Actions + one UI slice per domain)
- `lib/actions/{restaurant,hostel,staff}.ts` — authedAction wrappers over every
  RPC (AUTHORIZE→VALIDATE→MUTATE, zod input, IDOR guard, Postgres errors → Sentry)
- UI slices (RLS-scoped server fetch + client form → Server Action → RPC):
  `/restaurant/purchases` (createPurchase), `/hostel/rent` (recordRentPayment),
  `/staff/payroll` (run/approve). Bilingual strings (en/ta, 53 keys, parity
  checked). `next build` + tsc + lint + 47 Vitest all green

## Authored, needs owner credentials to run
- Supabase clients / health / backup / keep-alive: need Supabase, R2, CRON_SECRET
- Rate limiting: needs Upstash; Sentry seam: needs DSN (SDK wiring pending)
- Server Actions call the RPCs but need a live Supabase project + a signed-in
  session to exercise end-to-end (RPC logic itself verified on local PG16)

## Remaining (not yet built)
- **UI breadth**: forms/lists for the remaining flows (shifts, consumption/waste,
  counts, tenants/rent/reminders, roster/attendance/payroll, dashboards)
- **Client-side PDFs** (receipts, payslips) with @react-pdf/renderer
- **JWT auth hook** (0.7 optimization) + login/middleware runtime wiring
- **PWA** offline queue (serwist + Dexie), **Sentry SDK**, **restore-test**
  workflow, monthly integrity job, **reports/exports**, wa.me reminders
- Full breadth of the 359 features in FEATURE_LIST_V2.md

## Owner checklist (Group B — external accounts + secrets)
Supabase project (URL/anon/service_role/DATABASE_URL@6543/DIRECT_URL@5432) ·
Vercel (link + env + set `main` default + branch protection) · Brevo SMTP
(+SPF/DKIM) · Cloudflare R2 (+ SUPABASE_DB_URL/R2_* GitHub secrets) · Upstash ·
Sentry DSN · CRON_SECRET · UptimeRobot on /api/health · run `supabase db push`.
