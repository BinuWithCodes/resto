# CLAUDE.md — MASTER PROMPT
# Admin-Only Operations App: Restaurant Stock & Shift Ledger + Multi-Hostel Management + Staff Management

> **This file is the single source of truth and permanent memory for Claude Code (and any AI coding agent) building this project.**
> Read it fully before writing any code. Every rule here is binding. If a user prompt conflicts with this file, STOP and ask before proceeding.
> This is a PRODUCTION-GRADE system managing ₹16+ lakh/month of business activity on free-tier infrastructure. It is NOT a demo, NOT an MVP, NOT a prototype. Code accordingly.
> The complete requirements document is `FEATURE_LIST_V2.md` (359 numbered features). This file defines HOW to build them.

---

## 1. WHAT THIS APP IS — READ CAREFULLY, THE SCOPE IS UNUSUAL

An **internal, admin-only operations control panel** for one owner in Tamil Nadu, India who runs:

1. **One high-volume restaurant** — but this app is **NOT a POS**. Billing and accounting happen offline, standalone. The app records, per shift (**Breakfast / Lunch / Dinner**): income totals (by source and payment mode), expenses (with credit/payables), stock purchases, stock consumption, waste, and end-of-shift cash reconciliation with variance capture.
2. **Multiple hostels/PGs** (200+ long-term tenants across locations) — bed-level occupancy, tenant records (text-only KYC), rent invoicing + payment recording, deposits, utility bill splitting, move-out settlement, and meal plans that feed the restaurant's headcount.
3. **Shared staff** across all locations — records, duty roster, admin-marked attendance, leave, salary advances, payroll with payslips.

### 1.1 Exactly TWO user roles. Nobody else ever logs in.
- **`super_admin`** (the owner): sees and controls everything across all locations. Only role that can: approve payroll, reopen locked shifts, post stock adjustments, waive rent, approve move-out settlements, manage admin accounts, and change settings.
- **`admin`** (location manager): scoped to assigned location(s) via `memberships`. Does day-to-day data entry. CANNOT approve payroll, delete records, change settings, or see other locations' data.

There are **no customer, tenant, or staff logins**. No public pages except the login screen. Every piece of data is entered BY an admin ABOUT the business. This kills most attack-surface, bandwidth, and complexity concerns — do not reintroduce them.

### 1.2 NO PHOTO OR FILE UPLOADS — anywhere
All data is **text and numbers only**. No KYC images, no bill photos, no payment screenshots, no room photos, no inspection photos. Do not build upload forms, storage buckets, signed URLs, or image compression. Supabase Storage is unused. If a feature seems to want a photo, it wants a text note instead.

### 1.3 Explicitly OUT of scope — never build these, even if a prompt hints at them
POS / table billing / GST tax invoices / menus / QR customer ordering / kitchen display / loyalty / tenant self-service portal / complaints module / visitor logs / lease e-signing / staff self-service / salary structures (PF/ESI/HRA) / payment gateway integration / double-entry accounting ledgers / file or photo uploads. Financial accounting is done offline. This app is a **management ledger**, not an accounting system. If asked to add any of these, push back and confirm with the human first.

### 1.4 Locale (bake in everywhere)
- Currency **INR**. ALL money stored as **integer paise** (`bigint`) — never floats, never rupee decimals. Helpers in `/lib/money.ts` (`formatINR` with Indian digit grouping ₹1,23,456, pro-rata, late-fee, payroll math). Every money function ships with unit tests.
- Stock quantities: `numeric(12,3)` (kg/L need 3 decimals).
- Timezone `Asia/Kolkata`. Dates DD/MM/YYYY. "Business date" of a shift is the local calendar date.
- i18n via `next-intl`: `messages/en.json` + `messages/ta.json` (Tamil + English). **Never hardcode UI strings.**

---

## 2. TECH STACK (fixed — do not deviate without asking)

| Layer | Choice | Non-negotiable notes |
|---|---|---|
| Framework | Next.js (App Router) + TypeScript + React Server Components + Server Actions | |
| UI | Tailwind CSS + shadcn/ui (components copied into `/components/ui`, edit freely) | Mobile-first; every screen usable one-handed at 360px |
| DB / Auth / Realtime | **Supabase FREE tier** (Postgres) | RLS everywhere (§4.2). Storage NOT used (no uploads) |
| Hosting | **Vercel Hobby (free)** | 10s function timeout shapes PDF/query design (§3). Flag to human: Hobby ToS prohibits commercial use — Vercel Pro ($20/mo) is the one recommended paid upgrade for legitimacy + 60s timeout |
| PDF (receipts, payslips, reports) | `@react-pdf/renderer`, **generated CLIENT-SIDE in the browser** | Server-side PDF risks the 10s timeout. NEVER use Puppeteer/Playwright/headless Chrome |
| Offline entry queue | Dexie.js (IndexedDB) + **serwist** service worker | `next-pwa` is abandoned — use serwist. Disable SW in dev. serwist needs Webpack: build with `--webpack` on Next 16+ |
| Scheduled jobs | Vercel cron (2 free slots: DB keep-alive + daily dues/alerts) + **cron-job.org** (free) for precise-timing jobs, hitting `/api/cron/*` routes protected by a `CRON_SECRET` Authorization header | Vercel Hobby crons fire once/day, UTC, imprecise |
| Backups | **GitHub Actions nightly `pg_dump` → Cloudflare R2 (free 10 GB)** | Supabase free has NO backups and NO PITR. This job is the ONLY backup. It exists from Phase 0. Monthly automated restore test |
| Auth emails | **Custom SMTP: Brevo free (300/day)** wired into Supabase Auth | Supabase built-in SMTP ≈ 2–3 emails/hour — breaks admin invites/resets. Configure SPF/DKIM |
| Error monitoring | Sentry free (5,000 events/mo) with `beforeSend` filter + ~170/day cap; performance tracing OFF | One bad deploy can burn the whole month's quota in hours without the cap |
| Uptime | UptimeRobot free pinging `/api/health` (checks DB reachability) | |
| Rate limiting | `@upstash/ratelimit` + Upstash Redis free (500K commands/mo) on login + inside the action wrapper | Middleware doesn't cover Server Actions — limit inside them |
| Validation | `zod` on every input | |
| Notifications | `wa.me` deep links (pre-filled WhatsApp text; admin taps send). NO paid WhatsApp API, NO SMS, NO email to tenants | |

**Dependencies rule:** minimal. Before adding any package, check whether shadcn/existing deps cover it. No ORM — use the Supabase JS client with generated types (`supabase gen types typescript`).

---

## 3. FREE-TIER LIMITS — HARD WALLS THAT SHAPE THE ARCHITECTURE

| Resource | Limit | Failure mode | Mandatory workaround |
|---|---|---|---|
| Supabase DB | 500 MB | Full DB | Text-only rows are tiny; still: monthly archival of `audit_logs` + shift data older than 12 months → R2 CSV; aggregates retained |
| Supabase egress | 5 GB/mo | **Every request returns HTTP 402 — total outage** | Admin-only traffic (~5–10 users) makes this safe; keep payloads lean, paginate lists |
| Supabase auth emails | ~30/hr default | Admin invites stall | Brevo SMTP + raise the auth rate-limit setting |
| Supabase backups | NONE | Unrecoverable loss | Nightly pg_dump → R2 (§2); alert on failure; monthly restore test |
| Supabase projects | 2 | No hosted staging | Project 1 = production; staging = local `supabase start` (Docker); project 2 kept in reserve |
| Supabase inactivity | Pauses after 7 idle days | App down | Daily keep-alive cron (Vercel slot 1) |
| Vercel function timeout | 10 s | 504s | Client-side PDFs; paginated queries; no long server work |
| Vercel bandwidth | 100 GB/mo | Paused | Trivial at admin-only scale; keep it that way (no public pages) |
| Vercel crons | 2/day, imprecise | Missed jobs | cron-job.org for T-3/T-0/T+3 reminder generation etc. |
| GitHub Actions | 2,000 min/mo private | CI stops | Budget ≈ 210–450 min/mo (backup + CI) — fits; keep CI ≤ 10 min |
| Sentry | 5,000 events/mo | Silent drop | `beforeSend` + daily cap |
| Upstash | 500K commands/mo | Throttle | Ample at this scale |

**Usage monitoring is a feature:** a weekly job writes DB size and row counts to `system_metrics` and alerts the owner (dashboard banner + wa.me line in the daily summary) at 80% of any limit.

---

## 4. ARCHITECTURE RULES

### 4.1 Multi-location model
- One `organizations` row. `locations.type IN ('restaurant','hostel')`. Every business table carries `org_id` and (where relevant) `location_id`, both indexed.
- `memberships (user_id, location_id, role)` maps admins to locations; `super_admin` holds an org-wide membership.
- Custom JWT claims (`org_id`, `role`) injected via a Supabase Auth Hook at login.

### 4.2 Row-Level Security — the prime directive
- **Every table gets RLS enabled + policies + indexes IN THE SAME MIGRATION that creates it.** A table without RLS is a data breach (cf. CVE-2025-48757: 10%+ of AI-built Supabase apps had publicly readable tables). Turn ON the org setting "Enable RLS on new tables."
- Policy performance rules (Supabase official guidance):
  - Always `(select auth.uid())` — never bare `auth.uid()` (initPlan caching; 100×+ faster on large tables).
  - Always `TO authenticated`.
  - Separate policies per operation (SELECT/INSERT/UPDATE/DELETE); UPDATE gets both `USING` and `WITH CHECK`.
  - Multi-table role checks live in a `security definer` function (e.g. `has_location_access(loc_id uuid)`) in a **non-public schema**, wrapped in `(select ...)`.
  - Index every column referenced by any policy.
- With only two roles, policies are simple — keep them simple: `super_admin` → org-wide; `admin` → membership-scoped. Locked rows (§4.4) additionally reject writes for non-`super_admin`.
- `service_role` key: server-only env var, never in the client bundle, each use justified in a code comment.
- Run Supabase **Security Advisor + Performance Advisor before every release**; fix all findings or document why not.

### 4.3 Database connections
- All serverless code connects via the **Supavisor transaction-mode pooler (port 6543)**. Session mode (5432) only for migrations/admin scripts. No prepared-statement caching in transaction mode.

### 4.4 Data integrity (financial-grade, even without accounting)
- **Transactions:** any multi-table money/stock write — shift close, payroll run, stock adjustment, deposit settlement, purchase posting — is one Postgres transaction, implemented as a Postgres function called via RPC.
- **Idempotency:** every offline-synced or retryable mutation carries a client-generated UUID; `UNIQUE (device_id, idempotency_key)` + `INSERT ... ON CONFLICT DO NOTHING`, returning the stored result on replay. No duplicate shift entries or payments, ever.
- **Constraints:** FKs everywhere; `CHECK (amount_paise >= 0)`; `CHECK (qty >= 0)` where applicable; `UNIQUE` on receipt numbers (per location per financial-year series) and on `(location_id, shift_def_id, business_date)` for shift sessions.
- **Stock ledger pattern (mandatory):** ALL stock changes flow through ONE append-only `stock_movements` table (`item_id, location_id, movement_type IN ('purchase','purchase_return','consumption','waste','transfer_out','transfer_in','internal_issue','adjustment'), qty_delta numeric(12,3), rate_paise, ref_table, ref_id, shift_session_id, created_by`). Current stock = SUM(qty_delta) per item, cached in `stock_balances` maintained by trigger. **Never UPDATE a quantity in place.** Negative-stock guard enforced in the trigger. This is what makes shrinkage provable.
- **Audit:** Postgres triggers write INSERT-only rows to `audit_logs (actor, action, table_name, record_id, before jsonb, after jsonb, at)` for every money/stock table. No UPDATE/DELETE grants on `audit_logs`. Retain ≥ 1 year (DPDP Rule 6), then archive to R2.
- **Locking model:** `shift_sessions` and `payroll_runs` move to `locked` after close/approval; attendance locks after its payroll run. Post-lock edits require `super_admin` + a reason, and are audit-logged. Enforce in RLS + RPC — never only in the UI.

### 4.5 Server Action discipline (every single action)
Order is law: **(1) AUTHORIZE → (2) VALIDATE → (3) MUTATE.**
1. Verify session; verify role; verify membership on the specific `location_id` of the specific row being touched (re-read the resource server-side — never trust client-supplied `org_id`/`location_id`; defends IDOR).
2. `zod.safeParse` the input; return flattened field errors.
3. Mutate, inside a transaction where multi-table.
Build ONE `authedAction()` wrapper implementing this and use it for every action so forgetting is impossible. Rate-limit inside the wrapper (Upstash, keyed on user id). User-facing errors: plain language, bilingual; details go to Sentry only — never leak SQL or stack traces.

### 4.6 Directory layout
```
/app
  /(auth)            login, reset-password, invite-accept
  /(dashboard)       owner dashboard, analytics, alerts
  /(restaurant)      shifts, income, expenses, stock, purchases, suppliers, counts, waste, reports
  /(hostel)          locations, rooms-beds, tenants, rent, payments, deposits, utilities, moveout, meals, reports
  /(staff)           employees, roster, attendance, leave, advances, payroll, reports
  /(settings)        org, locations, shifts-config, categories, users, audit-log   [super_admin only]
  /api               health, cron/* (CRON_SECRET-protected)
/components/ui       shadcn
/components/*        feature components
/lib                 supabase clients, authedAction, money.ts, stock.ts, dates.ts, i18n
/db/migrations       numbered SQL, immutable once applied
/db/tests            pgTAP RLS + integrity tests
/messages            en.json, ta.json
/e2e                 Playwright specs
```

---

## 5. DATABASE SCHEMA (source of truth — extend, never restructure silently)

All tables text/numbers only — **no photo/file URL columns anywhere.**

**Identity & system:** `organizations` • `locations` • `users` (mirrors auth.users) • `memberships` • `audit_logs` • `system_metrics` • `notifications_log`.

**Restaurant / shift ledger:**
`shift_definitions` (name, start/end time, active) • `shift_sessions` (location, shift_def, business_date, status `open|closed|locked`, opening_cash_paise, expected_closing_cash_paise, actual_closing_cash_paise, variance_paise, variance_reason, handover_note, closed_by; UNIQUE(location, shift_def, business_date)) • `shift_income_entries` (session, source `dine_in|parcel|bulk|catering|other`, mode `cash|upi|card`, amount_paise, customer_count, note) • `expense_categories` • `shift_expense_entries` (session, category, description, amount_paise, mode `cash|upi|credit`, supplier_id nullable, settled boolean, settled_at).

**Stock:**
`stock_categories` • `stock_items` (name, category, base_unit, purchase_unit, conversion_factor, sku, perishable, shelf_life_days, reorder_level, reorder_qty, standard_rate_paise, preferred_supplier_id, active) • `suppliers` (name, phone, category, address, notes, rating) • `purchases` (supplier, location, date, payment_status `paid|credit`, total_paise, shift_session_id nullable, notes) • `purchase_items` (purchase, item, qty, rate_paise, line_total_paise) • `supplier_payments` (supplier, amount_paise, date, mode, note) • `consumption_templates` + `consumption_template_items` • `stock_movements` (append-only ledger, §4.4) • `stock_balances` (trigger-maintained cache) • `stock_counts` (location, date, status) + `stock_count_items` (item, system_qty, counted_qty, variance_qty, variance_value_paise, reason) • `waste_logs` (item, qty, reason_code, shift_session_id, cost_paise).

**Hostel:**
`rooms` (location, number, floor, type, amenities jsonb) • `beds` (room, label, status `vacant|occupied|notice|maintenance|reserved`) • `tenants` (name, phone, alt_phone, email, dob, gender, present_address, permanent_address, emergency_contact jsonb, occupation, **aadhaar_last4 text — ONLY the last 4 digits, ever**, consent_at timestamptz, join_date, rent_paise, deposit_paise, notice_days, status `active|notice|vacated|blacklisted`, notes) • `bed_assignments` (tenant, bed, from_date, to_date — history preserved) • `rent_invoices` (tenant, location, period, due_date, base_rent_paise, utility_paise, meal_paise, late_fee_paise, adjustment_paise, total_paise, status `due|partial|paid|waived`, receipt_no) • `rent_payments` (invoice, amount_paise, date, mode `upi|cash|bank`, confirmed_by, reversed boolean, reversal_reason) • `reminder_logs` (tenant, invoice, stage `t_minus_3|t0|t3|t7|t15`, sent_at, sent_by) • `deposit_transactions` (tenant, type `received|deduction|refund`, amount_paise, description) • `utility_bills` (location, type `electricity|water|gas`, period, total_paise, prev_reading, curr_reading, split_method) + `utility_splits` (bill, tenant, share_paise) • `moveouts` (tenant, notice_date, vacate_date, inspection_notes, dues_paise, damages_paise, refund_paise, status, approved_by) • `meal_plans` (name, meals_included, monthly_price_paise) • `meal_subscriptions` (tenant, plan, from_date, to_date, active) • `meal_skips` (tenant, date, meal).

**Staff:**
`employees` (name, phone, dob, gender, addresses, emergency_contact jsonb, designation, monthly_salary_paise, bank_upi_reference text, status `active|on_leave|left`, join_date, exit_date, exit_reason, notes) • `roster_entries` (employee, location, date, shift `breakfast|lunch|dinner|full|night`; overlap-conflict checked) • `attendance` (employee, location, date, status `present|absent|half|leave|weekoff`, late_minutes, ot_hours, locked boolean) • `leave_types` + `leave_balances` + `leaves` • `advances` (employee, amount_paise, reason, status `requested|approved|paid`, approved_by, instalments) + `advance_deductions` • `payroll_runs` (period, scope, status `draft|approved|locked`, approved_by) + `payroll_items` (employee, gross_paise, leave_deduction_paise, advance_deduction_paise, ot_paise, bonus_paise, net_paise, paid_marked boolean, paid_at).

**Derivations, not duplications:** dashboards read from views/materialized aggregates (`daily_summaries`, `stock_valuation_view`, `collection_efficiency_view`). Never store a number twice that can be derived — except audited caches (`stock_balances`).

---

## 6. FEATURE SCOPE (summary — full spec is FEATURE_LIST_V2.md, 359 features)

1. **Restaurant (1–92):** shift setup + lock; per-shift income entry (source + mode split + customer count); per-shift expenses with credit/payables and supplier tagging; shift close with cash reconciliation, mandatory variance reason, checklist, handover note, P&L snapshot; stock master with unit conversion + reorder levels + standard rates; purchases with rate-variance and duplicate warnings; consumption with quick-entry templates; transfers to hostel mess; internal issues; physical counts with shrinkage reporting; waste with reason codes; alerts ("what to buy today", expiry, dead stock, price-rise); supplier management with outstanding payables and price comparison; reports incl. food-cost proxy and stock movement.
2. **Hostel (93–194):** locations; rooms/beds with colour-coded occupancy grid + bulk creation + transfers; tenant records with text-only KYC (aadhaar_last4, consent timestamp); rent invoicing (pro-rata, late fees, waivers, revisions, receipt numbering per FY, revenue-stamp flag on cash receipts > ₹5,000); payment recording (partial, advance, oldest-first allocation, reversal); wa.me reminder workflow (T-3/T0/T+3/T+7/T+15, bulk mode, reminder log, escalation flags); deposit ledger + move-out settlement with super_admin approval; utility splitting (4 methods) feeding invoices; meal plans feeding restaurant headcount + mess profitability; reports (occupancy, collection efficiency, defaulter aging, vacancy forecast).
3. **Staff (195–259):** records with flat monthly salary; cross-location roster with conflict detection, copy-week, templates, WhatsApp share, "who's on duty now"; bulk attendance marking with late/OT capture and post-payroll lock; leave with balances and unpaid-leave flags; advances with approval + instalment deductions + outstanding report; payroll (salary − unpaid leave − advances + OT + bonus) with preview, super_admin approval, payslip PDF, wa.me share, lock; reports incl. staff cost allocation across businesses.
4. **Dashboard & cross-cutting (260–329):** two-role auth with permission matrix, login audit, optional 2FA; owner dashboard cards (today's net, shift statuses, occupancy, collection %, defaulters, low stock, stock value, staff on duty, payables, advances outstanding, cash position, alerts feed); unified analytics (business/location/shift comparison, food-cost %, cost per bed, MoM/YoY); alert config + wa.me daily summary; Tamil/English; PWA with offline entry queue; audit views; data export; settings (super_admin only).
5. **Engineering (330–359):** encoded throughout this file.

---

## 7. INDIA COMPLIANCE (reduced scope, still real)

- **NO GST invoicing** — billing is offline. Do not build tax invoices. Rent receipts are simple receipts, not tax invoices.
- **Revenue stamp:** cash rent receipts over ₹5,000 need a ₹1 revenue stamp (Indian Stamp Act). The receipt PDF shows a stamp box + reminder when `mode='cash' AND amount_paise > 500000`. Not needed for UPI/bank.
- **Aadhaar (hard rule):** NEVER store, log, or accept a full 12-digit Aadhaar number anywhere — not in Postgres, not in Sentry, not in exports (UIDAI restricts full-number storage to Aadhaar Data Vaults; Aadhaar Act §37 penalties apply). The `tenants.aadhaar_last4` field holds exactly 4 digits; validate `^[0-9]{4}$` and reject longer input at both Zod and CHECK-constraint level.
- **DPDP Act 2023 + Rules 2025** (full compliance due May 2027; penalties to ₹250 crore): record a plain-language consent timestamp (English + Tamil notice) at tenant/employee onboarding; data minimisation (text-only KYC keeps this easy); audit logs retained ≥ 1 year; per-person data export; deletion/archival after vacate + retention period; breach-notification template kept in the repo.

---

## 8. TESTING & CI — MERGE GATES, NOT SUGGESTIONS

- **Vitest unit tests (pure functions):** rent pro-rata, late fees, oldest-first payment allocation, deposit settlement, payroll math (leave/advance/OT/bonus), stock math (opening + in − out − waste = closing), unit conversion, variance calc, INR formatting. **Every money/stock function ships WITH its tests in the same PR.**
- **pgTAP (run via `supabase test db` in CI):** `tests.rls_enabled('public')` asserts RLS on ALL tables; policy tests with `tests.create_supabase_user()` proving: an admin of Hostel A gets `is_empty` on Hostel B rows; an admin cannot approve payroll; locked shift sessions reject UPDATE (`throws_ok`); `audit_logs` rejects UPDATE/DELETE; negative stock is blocked.
- **Playwright E2E (critical money paths only):** shift open → entries → close → variance → lock; rent invoice → payment → receipt; payroll draft → approve → payslip. Tests independent, unique seeded users.
- **CI pipeline (GitHub Actions, every PR):** typecheck → lint → Vitest → local Supabase + migrations + pgTAP → build. Branch protection on `main`; merges blocked on red; E2E on main merges. Keep total CI ≤ 10 min.
- **Migrations:** numbered SQL in `/db/migrations`, immutable once applied; tested on local Docker Supabase before `db push` to production; no destructive migration without an explicit human-confirmed plan + a fresh backup taken first.

---

## 9. OFFLINE & PWA

Installable PWA (serwist). Precache the app shell; runtime-cache reads; **queue writes** (shift entries, attendance, stock entries) in Dexie with idempotency keys when offline; visible "offline — N pending" badge; sync on reconnect through the same server actions (idempotent, §4.4). `reloadOnOnline: false` (don't wipe in-progress forms). Background Sync API is Chromium-only — include a retry-on-focus fallback. Service worker versioning: prompt-to-refresh on new deploys; include a schema-version handshake and force refresh on mismatch so a stale client never writes against a new schema.

## 10. OBSERVABILITY & OPERATIONS

- Sentry on client + server actions (filtered, capped). `/api/health` checks DB reachability; UptimeRobot pings it.
- Weekly `system_metrics` job (DB size, row counts) + 80%-of-limit alerts (§3).
- Nightly backup workflow with failure alert; monthly restore-test workflow (restore into local Docker, run integrity checks).
- Monthly integrity job: orphan-FK scan, receipt-number sequence gaps, stock ledger vs balances reconciliation.
- `RUNBOOK.md` (one page, kept current): restore a backup; resume a paused Supabase project; rotate keys; switch SMTP; roll back a Vercel deploy (promote previous deployment).

---

## 11. BUILD ORDER (finish and live-test each phase before starting the next)

- **Phase 0 — Foundation:** repo, CI skeleton, Vercel + Supabase wiring, Brevo SMTP, auth + roles + memberships + JWT claims, base schema migration WITH RLS + pgTAP harness, `authedAction` wrapper, dashboard shell, PWA + i18n scaffold, **nightly backup + keep-alive cron + Sentry + health check**. Nothing else starts until Phase 0 is green.
- **Phase 1 — Restaurant shift ledger + stock:** shift definitions/sessions → income/expense entry → shift close + reconciliation + lock → stock master + suppliers → purchases → consumption + templates → movements ledger + balances → waste → counts + variance → alerts → reports. **Live-test one full week of real shifts.**
- **Phase 2 — Hostel:** locations/rooms/beds + occupancy grid → tenants + consent → rent invoicing cron → payments + receipts → reminders (wa.me) → deposits → utilities → move-out → meal plans (+ headcount feed to restaurant). Onboard ONE hostel live, then replicate.
- **Phase 3 — Staff:** records → roster → attendance → leave → advances → payroll + payslips + lock.
- **Phase 4 — Dashboard & analytics:** owner cards, unified analytics, alert config, exports, wa.me daily summary.
- **Phase 5 — Hardening:** offline queue polish, archival job, restore-test automation, advisor sweeps, RUNBOOK finalisation.

---

## 12. HOW TO WORK WITH THE HUMAN (a solo vibe coder)

1. **Plan before code** on any non-trivial task: short plan → wait for OK. Schema changes ALWAYS get explicit approval first.
2. **Small diffs, one task at a time.** After each change: list files touched, flag anything that could break existing features, and give a 3-line manual test script ("open X, do Y, expect Z").
3. **Never** run destructive commands (drops, bulk deletes, prod data edits) without an explicit warning and confirmation. Never experiment against production.
4. Every money/stock change ships with its unit test. `tsc --noEmit` + lint must pass before presenting work as done.
5. If this file seems wrong or outdated, say so explicitly — do not silently deviate. If a requested feature is in §1.2/§1.3 (out of scope), push back and confirm.
6. Prefer boring, conventional, well-documented patterns. This codebase must remain understandable and regenerable by AI tools.

**Definition of production-grade for this project (the bar for "done"):** RLS proven by tests, money math proven by tests, every financial write transactional + idempotent, shift/payroll locking enforced in the database, nightly backups with a tested restore, monitoring wired to the owner's phone, DPDP-safe text-only KYC, and a runbook a non-expert can follow at 11 PM when something breaks.
