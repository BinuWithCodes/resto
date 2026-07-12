# Resto

Internal, **admin-only** operations console for one owner in Tamil Nadu running a
high-volume restaurant, multiple hostels/PGs, and shared staff. It is a
**management ledger — not a POS, not an accounting system.** Text and numbers
only; no photo/file uploads anywhere.

> **The binding contract for this project is [`CLAUDE.md`](./CLAUDE.md).** Read it
> fully before changing anything — it wins over any other instruction source.
> The full requirements spec is [`FEATURE_LIST_V2.md`](./FEATURE_LIST_V2.md)
> (359 features). The current build plan is in [`docs/`](./docs).

## Stack

Next.js 16 (App Router, RSC + Server Actions) · TypeScript (strict) · Tailwind v4
with shadcn/ui · Supabase (Postgres, RLS everywhere) · Vercel · next-intl (Tamil
and English) · Vitest + pgTAP + Playwright. Money is stored as **integer paise**;
stock as `numeric(12,3)`. See CLAUDE.md §2 for the full, fixed stack.

## Scripts

| Command                           | What it does           |
| --------------------------------- | ---------------------- |
| `npm run dev`                     | Local dev server       |
| `npm run build`                   | Production build       |
| `npm run typecheck`               | `tsc --noEmit`         |
| `npm run lint`                    | ESLint                 |
| `npm run test`                    | Vitest (unit tests)    |
| `npm run format` / `format:check` | Prettier write / check |

`typecheck` + `lint` + `test` must pass before any change is presented as done
(CLAUDE.md §12).

## Layout

App routes are grouped by area under `app/` — `(auth)`, `(dashboard)`,
`(restaurant)`, `(hostel)`, `(staff)`, `(settings)` — with `lib/` (Supabase
clients, `authedAction`, money/stock/date helpers), `db/migrations` (numbered,
immutable), `db/tests` (pgTAP), `messages/` (en/ta), and `e2e/` (Playwright).
See CLAUDE.md §4.6.

## Setup

1. `npm install`
2. Copy `.env.example` → `.env.local` and fill values (see the file for which are
   server-only). Production values go in Vercel env vars, never committed.
3. `npm run dev`

Local Supabase (staging) runs via Docker: `supabase start`. There is **no hosted
staging** (free tier = 2 projects; one is production, one is held in reserve).
