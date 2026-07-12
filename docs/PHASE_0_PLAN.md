# Phase 0 — Foundation Plan

> Status: **AWAITING OWNER APPROVAL** — no step executes until approved (CLAUDE.md §12.1).
> Scope source: CLAUDE.md §11 Phase 0. Nothing outside this list starts until Phase 0 is green.
> Every schema step additionally requires its own explicit approval of the migration SQL before it is written/applied.

## Known blockers (must be resolved by the owner)

1. **`FEATURE_LIST_V2.md` is not in the repo.** CLAUDE.md names it as the binding 359-feature spec. Phase 0 can proceed on CLAUDE.md alone (its §5/§6 cover foundation scope), but Phase 1 must not start without it. → Owner: add the file to the repo root.
2. **External accounts** (owner-actioned; agent cannot create these): Supabase production project, Vercel project, Brevo account + SPF/DKIM on the sending domain, Cloudflare R2 bucket + API token, Upstash Redis, Sentry project, UptimeRobot monitor, cron-job.org account. Each step below lists exactly which secrets it needs.
3. **Skills from the kickoff doc** (superpowers, ui-ux-pro-max, frontend-design, lean-ctx, Playwright MCP) are not installed in the remote environment. Their *methodologies* are applied manually: plan→approve→execute with review, strict red/green TDD on test-gated code, a written design system in `design-system/MASTER.md` before any UI, lean context habits, and Playwright E2E + 360px visual verification. If the owner installs the plugins locally, later sessions use them directly.

## Steps

Each step is a small, independently testable diff. Order matters; steps marked ⛔ have a hard approval gate.

### 0.1 Repo scaffold
Next.js (App Router) + TypeScript strict + Tailwind + shadcn/ui initialised; directory layout per CLAUDE.md §4.6 (empty route groups with placeholder pages); ESLint + Prettier; `.env.example` listing every env var the project will ever need (documented, no values); `.gitignore`; `README.md` stub pointing at CLAUDE.md.
**Verify:** `npm run build`, `tsc --noEmit`, `npm run lint` all pass locally.

### 0.2 CI skeleton (GitHub Actions)
Workflow on every PR: typecheck → lint → Vitest → (from 0.5 on) local Supabase + migrations + pgTAP → build. Concurrency-cancel on stale runs; target ≤ 10 min total. Owner enables branch protection on `main` (merges blocked on red).
**Verify:** green run on a trivial PR; workflow duration reported.

### 0.3 Supabase wiring (local-first)
`supabase init`; local stack via `supabase start` (Docker) = the staging environment; `supabase gen types typescript` script; server/client Supabase helpers in `/lib` (browser client, server client, service-role client with justification comments). Serverless connections documented to use Supavisor transaction pooler (port 6543); session mode (5432) reserved for migrations.
**Needs from owner:** production project ref + anon key + service_role key + DB password (Vercel env vars only; never committed).
**Verify:** `supabase status` healthy locally; a trivial round-trip query against local DB from a script.

### 0.4 Vercel wiring
Project linked, env vars set, preview deploys on PRs. Flag on record (CLAUDE.md §2): Vercel Hobby ToS prohibits commercial use — Pro ($20/mo) is the recommended paid upgrade.
**Verify:** preview URL serves the scaffold; production deploy of the shell.

### 0.5 ⛔ Base schema migration #1 — identity & system tables
`organizations`, `locations`, `users` (mirror of auth.users via trigger), `memberships`, `audit_logs`, `system_metrics`, `notifications_log` — **each with RLS enabled + per-operation policies + indexes in the same migration** (§4.2); `has_location_access(loc_id)` security-definer helper in a non-public schema; audit trigger function; `(select auth.uid())` form throughout.
**Gate:** full SQL presented for explicit approval BEFORE it is written into `/db/migrations`.
**Verify:** applies cleanly on local Docker Supabase; pgTAP (0.6) green.

### 0.6 pgTAP harness (red → green)
`supabase test db` wired locally and in CI. First tests: `tests.rls_enabled('public')` across ALL tables; seeded test users proving membership scoping (admin of location A gets `is_empty` on location B rows); `audit_logs` rejects UPDATE/DELETE (`throws_ok`). Written red-first against 0.5.
**Verify:** deliberately-broken policy fails the suite; fixed policy passes; suite runs in CI.

### 0.7 Auth + roles + JWT claims
Supabase Auth with a Custom Access Token Hook injecting `org_id` + `role` into the JWT; `(auth)` route group: login, reset-password, invite-accept; session middleware; role read from claims server-side.
**Needs from owner:** Brevo SMTP creds wired into Supabase Auth settings (+ SPF/DKIM verified, auth email rate limit raised) — owner-actioned in dashboards; I supply a step-by-step checklist.
**Verify:** manual: invite an admin → email arrives via Brevo → accept → login → decoded JWT shows `org_id`/`role`; pgTAP claim-dependent policies pass.

### 0.8 `authedAction()` wrapper
The single wrapper enforcing AUTHORIZE → VALIDATE → MUTATE (§4.5): session + role check, membership re-read on the target row's `location_id` (IDOR defense), `zod.safeParse` with flattened bilingual field errors, Upstash rate limit keyed on user id, Sentry capture (details never leaked to client). Ships with Vitest unit tests in the same commit (mocked Supabase/Upstash).
**Needs from owner:** Upstash Redis URL + token.
**Verify:** Vitest suite covering: unauthenticated reject, wrong-location reject, invalid-input field errors, rate-limit trip, happy path.

### 0.9 Design system + dashboard shell + i18n scaffold
First `design-system/MASTER.md` (written before any UI code): high-density ops-dashboard style, large touch targets for one-handed 360px use, minimal motion, strong contrast (bright kitchen/office), numeric-keypad-first inputs, bilingual layout rules (Tamil strings run ~30–40% longer). Then the shell: responsive nav (dashboard/restaurant/hostel/staff/settings groups), `settings` gated to super_admin, language switcher; `next-intl` with `messages/en.json` + `messages/ta.json`, zero hardcoded strings.
**Verify:** browser check at 360px viewport (screenshot); locale toggle renders both languages; `tsc` + lint green.

### 0.10 PWA scaffold
serwist service worker (disabled in dev; `--webpack` build flag noted for Next 16+), manifest + icons, app-shell precache, `reloadOnOnline: false`, versioning with prompt-to-refresh and schema-version handshake stub. Dexie DB schema + idempotency-key generator defined now (used by Phase 1 entry forms; full offline queue polish is Phase 5).
**Verify:** production build installable (Lighthouse PWA pass); SW registers in prod, absent in dev.

### 0.11 Ops & safety rails
`/api/health` (DB reachability, JSON status); Sentry client + server with `beforeSend` filter and daily cap, tracing OFF; Vercel cron slot 1 = keep-alive hitting a `CRON_SECRET`-protected route; **nightly GitHub Actions `pg_dump` → Cloudflare R2** with failure alert — this is the ONLY backup and exists from Phase 0; monthly restore-test workflow (restore into Docker, run pgTAP); first-draft `RUNBOOK.md` (restore, resume paused project, rotate keys, switch SMTP, roll back deploy).
**Needs from owner:** R2 bucket + token, Sentry DSN, `CRON_SECRET` value, UptimeRobot monitor on `/api/health`.
**Verify:** health endpoint returns `{db:"ok"}` in prod; backup workflow manually dispatched → object appears in R2; restore-test workflow run once successfully.

### 0.12 Phase 0 exit review
Supabase Security Advisor + Performance Advisor clean (or findings documented); CI fully green including pgTAP; all §11 Phase 0 items checked off with the owner before Phase 1 begins.

## Standing rules in force for every step (CLAUDE.md §12)

- Plan before code on any non-trivial task; **schema changes always get explicit approval before the migration is written**.
- Small diffs, one task at a time; after each change: files touched, breakage risks, 3-line manual test script.
- Every table created WITH its RLS policies and indexes in the same migration; every money/stock function ships with unit tests in the same commit.
- No destructive commands without warning + confirmation; never touch production data.
- `tsc --noEmit` + lint + tests green before any work is presented as done.
