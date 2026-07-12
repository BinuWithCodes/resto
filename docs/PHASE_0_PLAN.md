# Phase 0 — Foundation Plan

> Status: **plan approved for execution pending final go-ahead on Step 0.1.** Schema steps (⛔) still get their SQL approved individually before anything is written (CLAUDE.md §12.1).
> Scope source: CLAUDE.md §11 Phase 0. Nothing outside this list starts until Phase 0 is green.

## Decisions locked (owner-approved)

- **Branching:** `main` is the default, protected base branch. Work lands on `claude/claude-md-kickoff-c345zi` and merges into `main` via PR; CI + branch protection gate the merge (CLAUDE.md §8). `main` has been created at the initial commit; owner sets it as the default branch in GitHub → Settings → Branches.
- **RLS source of truth:** policies call a security-definer `has_location_access(loc_id)` (and a role check) that read the **`memberships` table**, NOT the JWT. This makes the pgTAP suite (0.6) fully testable before any auth wiring exists (0.7 becomes independent). JWT claims (`org_id`/`role`) are added in 0.7 purely as a query-time optimization, never as the sole authority.

## Known blockers (owner-actioned)

1. **`FEATURE_LIST_V2.md` is not in the repo.** Phase 0 runs on CLAUDE.md alone (§5/§6 cover foundation scope), but **Phase 1 must not start without it.** → Owner: add it to the repo root.
2. **External accounts** (agent cannot create these): Supabase production project, Vercel project, Brevo + SPF/DKIM, Cloudflare R2 bucket + token, Upstash Redis, Sentry project, UptimeRobot, cron-job.org. Each step lists the exact secret it needs.
3. **Kickoff skills** (superpowers, ui-ux-pro-max, frontend-design, lean-ctx, Playwright MCP) are NOT installed in this remote session and would not persist here. Their *methodologies* are applied by hand: plan→approve→execute-with-review, strict red/green TDD on test-gated math, a written `design-system/MASTER.md` before any UI, lean context habits, Playwright E2E + 360px checks (using the pre-installed Chromium where the harness allows).

## Remote-environment reality (affects *verification*, not authoring)

This is an ephemeral cloud container. I can author all config, migrations, tests, and workflows here, but some **verification** cannot run in this session and shifts to CI or your local machine:
- **Docker-dependent** (`supabase start`, local pgTAP run, restore-test): runs in **CI** and on your local machine, not here.
- **Vercel CLI linking / deploys**: **owner-local**, needs your account tokens.
- **Lighthouse / 360px browser checks**: best-effort here with Chromium; authoritative pass is on your device.
Each step's **Verify** line below is tagged with *where* it is verified.

## Execution order (front-load autonomous work)

**Group A — I can do now, no credentials needed:** 0.1, 0.2 (minimal), 0.5 (draft SQL for approval), 0.6, 0.8, 0.9. These produce reviewable diffs and green CI without any account setup.
**Group B — needs your secrets, batched so you unblock in one pass:** 0.3 (prod keys), 0.4 (Vercel), 0.7 (Brevo), 0.11 (R2/Sentry/CRON_SECRET/UptimeRobot).
I'll drive Group A to green first, hand you a single consolidated secrets checklist for Group B, then wire Group B as secrets arrive.

## Steps

Each step is a small, independently testable diff. ⛔ = hard SQL-approval gate.

### 0.1 Repo scaffold  · [Group A]
Next.js (App Router, **pinned Next 16.x**) + TypeScript strict + Tailwind + shadcn/ui; directory layout per CLAUDE.md §4.6 (empty route groups with placeholder pages); **Vitest installed + configured with one trivial passing test** (so CI is green from day one); ESLint + Prettier; `.env.example` documenting every env var (no values); `.gitignore`; `README.md` stub pointing at CLAUDE.md. All key deps **version-pinned** and their Next-16/serwist/next-intl/shadcn compatibility verified together (this combo is the top integration risk — pin deliberately).
**Verify [here]:** `npm run build`, `tsc --noEmit`, `npm run lint`, `npm run test` all pass in this session.

### 0.2 CI skeleton — minimal first  · [Group A]
GitHub Actions on every PR: **typecheck → lint → Vitest → build** to start; concurrency-cancel stale runs; ≤ 10 min. The **local-Supabase + migrations + pgTAP** stage is added in 0.6 (it has nothing to run before then). Owner enables branch protection on `main` (merges blocked on red).
**Verify [CI]:** green run on the Phase 0 PR; duration reported.

### 0.3 Supabase wiring (local-first)  · [Group B: prod keys]
`supabase init`; local Docker stack = staging; `supabase gen types typescript` script; `/lib` helpers (browser client, server client, service-role client each with a justification comment). Serverless connections documented to use the Supavisor transaction pooler (**6543**); session mode (**5432**) reserved for migrations/admin scripts. **Migrations are forward-only** (§8) — correct mistakes with a new migration, never by editing an applied one.
**Needs from owner:** prod project ref + anon key + service_role key + DB password (Vercel env only; never committed).
**Verify [CI + owner-local]:** `supabase status` healthy; trivial round-trip query against local DB.

### 0.4 Vercel wiring  · [Group B: Vercel]
Project linked, env vars set, preview deploys on PRs. On record (CLAUDE.md §2): Vercel Hobby ToS prohibits commercial use — Pro ($20/mo) is the recommended upgrade (60s timeout + legitimacy).
**Verify [owner-local]:** preview URL serves the scaffold; production deploy of the shell.

### 0.5 ⛔ Base schema migration #1 — identity & system  · [Group A: draft SQL]
`organizations`, `locations`, `users` (mirror of auth.users via trigger), `memberships`, `audit_logs`, `system_metrics`, `notifications_log` — **each with RLS + per-operation policies + indexes in the same migration** (§4.2). Security-definer `has_location_access(loc_id)` + role helper in a **non-public schema**, reading `memberships` (per the locked RLS decision); audit trigger function writing INSERT-only rows; `(select auth.uid())` form throughout; `audit_logs` has no UPDATE/DELETE grants.
**Gate:** full SQL presented for explicit approval BEFORE it is written into `/db/migrations`.
**Verify [CI]:** applies cleanly on local Docker Supabase; pgTAP (0.6) green.

### 0.6 pgTAP harness (red → green)  · [Group A]
`supabase test db` wired locally and in CI, and the pgTAP stage added to 0.2's workflow. **Seed/fixtures strategy defined here** (a repeatable seed script + `tests.create_supabase_user()` for role/membership fixtures) — reused later by E2E. First tests: `tests.rls_enabled('public')` across ALL tables; membership scoping (admin of location A gets `is_empty` on location B); `audit_logs` rejects UPDATE/DELETE (`throws_ok`). **Self-contained** — no dependency on 0.7, because policies read `memberships`, not JWT. Written red-first against 0.5.
**Verify [CI]:** a deliberately-broken policy fails the suite; fixed policy passes; suite runs in CI.

### 0.7 Auth + roles + JWT claims  · [Group B: Brevo]
Supabase Auth with a Custom Access Token Hook injecting `org_id` + `role` into the JWT **as an optimization** (policies already work without it via 0.5's function); `(auth)` route group: login, reset-password, invite-accept; session middleware; role read server-side.
**Needs from owner:** Brevo SMTP wired into Supabase Auth (+ SPF/DKIM verified, auth email rate limit raised) — I supply a step-by-step checklist.
**Verify [owner-local]:** invite admin → email via Brevo → accept → login → decoded JWT shows `org_id`/`role`; claim-optimized policies still pass pgTAP.

### 0.8 `authedAction()` wrapper  · [Group A]
The single wrapper enforcing AUTHORIZE → VALIDATE → MUTATE (§4.5): session + role check, membership re-read on the target row's `location_id` (IDOR defense), `zod.safeParse` with flattened bilingual field errors, Upstash rate limit keyed on user id, Sentry capture (details never leaked). **Defines the idempotency-key seam** (client UUID → `ON CONFLICT DO NOTHING`) even though no mutation uses it until Phase 1. Ships with its Vitest suite in the same commit (mocked Supabase/Upstash).
**Verify [here]:** Vitest covers unauthenticated reject, wrong-location reject, invalid-input field errors, rate-limit trip, happy path.

### 0.9 Design system + dashboard shell + i18n  · [Group A]
`design-system/MASTER.md` written **before any UI code**: high-density ops-dashboard style, large 360px one-handed touch targets, minimal motion, strong contrast (bright kitchen/office), numeric-keypad-first inputs, bilingual layout rules (Tamil runs ~30–40% longer). (This doc is additive to the §4.6 layout.) Then the shell: responsive nav (dashboard/restaurant/hostel/staff/settings), `settings` gated to super_admin, language switcher; `next-intl` with `messages/en.json` + `messages/ta.json`, zero hardcoded strings.
**Verify [here best-effort + owner-local authoritative]:** 360px render check; locale toggle renders both languages; `tsc` + lint green.

### 0.10 PWA scaffold  · [Group A authoring / owner-local verify]
serwist SW (disabled in dev; `--webpack` build flag for Next 16+), manifest + icons, app-shell precache, `reloadOnOnline: false`, versioning with prompt-to-refresh + schema-version handshake stub. Dexie schema + idempotency-key generator defined now (used by Phase 1 forms; full offline polish is Phase 5).
**Verify [owner-local]:** production build installable (Lighthouse PWA pass); SW registers in prod, absent in dev.

### 0.11 Ops & safety rails  · [Group B: R2/Sentry/CRON_SECRET/UptimeRobot]
`/api/health` running a **cheap `select 1`** (NOT a real table read — avoids burning egress on every UptimeRobot ping) returning JSON status; Sentry client + server with `beforeSend` filter and a **~170/day cap backed by an Upstash counter** (serverless can't use in-memory), tracing OFF; Vercel cron **slot 1** = keep-alive (**slot 2 reserved** for Phase 2 dues/alerts); **nightly GitHub Actions `pg_dump` → Cloudflare R2** with failure alert — the ONLY backup, exists from Phase 0; monthly restore-test workflow (restore into Docker, run pgTAP); first-draft `RUNBOOK.md` (restore, resume paused project, rotate keys, switch SMTP, roll back deploy).
**Needs from owner:** R2 bucket + token, Sentry DSN, `CRON_SECRET`, UptimeRobot monitor on `/api/health`.
**Verify [CI + owner]:** health returns `{db:"ok"}` in prod; backup workflow dispatched → object in R2; restore-test run once successfully.

### 0.12 Phase 0 exit review
Supabase Security + Performance Advisor clean (or findings documented); CI fully green including pgTAP; all §11 Phase 0 items checked off with the owner before Phase 1.

## Standing rules in force for every step (CLAUDE.md §12)

- Plan before code; **schema changes always get explicit approval before the migration is written**.
- Small diffs, one task at a time; after each: files touched, breakage risks, 3-line manual test script.
- Every table created WITH its RLS policies and indexes in the same migration; every money/stock function ships with unit tests in the same commit.
- No destructive commands without warning + confirmation; never touch production data.
- `tsc --noEmit` + lint + tests green before any work is presented as done.
