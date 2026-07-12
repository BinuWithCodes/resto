# Resto — Design System (MASTER)

> The binding UI reference for this project. Priority for any UI decision:
> **CLAUDE.md constraints > this document > individual taste.** Every screen
> built must follow this file. It is additive to the `app/` layout in CLAUDE.md §4.6.

## 1. What this product is (design-wise)

An **internal operations console** — data-entry-heavy, admin-only, used one-handed
on a phone in a bright kitchen or a cramped hostel office, often at speed at the
end of a shift. It is **not** a marketing site. Optimise for **information
density, speed of entry, and legibility in glare** — never for decoration.

Design goals, in order: **(1) fast numeric entry, (2) legibility at 360px in
bright light, (3) high information density, (4) calm, low-motion surfaces.**

## 2. Non-negotiables (from CLAUDE.md)

- **Mobile-first, usable one-handed at 360px.** Design the 360px layout first;
  scale up with breakpoints. The primary action on any entry screen sits within
  thumb reach (bottom half of the viewport).
- **Bilingual (Tamil + English), never hardcoded.** All strings come from
  `messages/en.json` + `messages/ta.json` via next-intl. **Tamil runs ~30–40%
  longer and taller** — never fix widths to English text; let buttons/labels
  wrap or grow, test both locales, and give line-height headroom for Tamil glyphs.
- **No photos/files anywhere.** No avatars, no image placeholders, no upload
  affordances. Represent everything with text, numbers, and colour.
- **Money is integer paise**, always rendered via `formatINR` with Indian digit
  grouping (₹1,23,456). Never show raw paise or floats.

## 3. Tokens

Colour is driven by the shadcn CSS variables in `app/globals.css` (neutral base,
light + dark). Use **semantic tokens** (`bg-background`, `text-foreground`,
`text-muted-foreground`, `border-border`, `bg-primary`, `text-destructive`),
never raw hex. Dark mode is supported via the `.dark` class (optional, per
feature 310).

**Status colour language** (occupancy grid, shift status, dues aging) — meaning
must never rely on colour alone; always pair with a text label or icon:

| Meaning | Token intent |
| --- | --- |
| Good / paid / occupied-ok / present | `emerald` |
| Warning / due-soon / notice / half-day | `amber` |
| Bad / overdue / variance / absent | `red` |
| Neutral / vacant / not-started | `muted` |
| Info / reserved / locked | `blue` |

Add these as extra CSS variables when the first status UI is built; keep them
colour-blind-safe (pair with labels/icons).

### Spacing, radius, type

- Base unit **4px**; dense screens use 8/12/16 rhythm, not 24/32.
- Radius from `--radius` (0.625rem); cards `rounded-lg`, inputs `rounded-md`.
- Font: system sans (Geist) for UI; **tabular numbers** for all money/quantity
  columns (`font-variant-numeric: tabular-nums`) so figures align.
- Type scale (mobile): body 16px (never below 14px for data), section headings
  18–20px, card labels 12–13px uppercase-tracked. 16px inputs to avoid iOS zoom.

## 4. Touch & interaction

- **Minimum touch target 44×44px** (48px preferred for primary actions).
  Spacing between adjacent targets ≥ 8px.
- **Numeric-keypad-first:** every money/quantity field uses
  `inputMode="decimal"` (or `numeric`), `enterKeyHint`, and selects-on-focus.
  Money entry is in **rupees** in the UI, converted to paise on submit.
- **Minimal motion:** transitions ≤ 150ms, opacity/transform only. Respect
  `prefers-reduced-motion`. No parallax, no decorative animation.
- **Recent-items & templates** beat free typing: surface last-used items,
  suppliers, and consumption templates as one-tap chips (features 50, 54, 309).
- **Offline affordance:** a persistent "offline — N pending" badge when the PWA
  queue has unsynced writes (§9 CLAUDE.md). Never block entry when offline.

## 5. Layout & navigation

- **App shell:** a compact top bar (context: current location + language switch)
  and a **bottom navigation** on mobile (thumb-reachable) across the areas:
  Dashboard · Restaurant · Hostel · Staff · Settings. On ≥ md, the bottom nav
  becomes a left sidebar.
- **Settings is super_admin-only** — hidden entirely for `admin` (not just
  disabled), enforced server-side; the nav simply omits it.
- **Location scope** is always visible: an `admin` sees only their location(s);
  the owner gets an all-locations filter.
- Lists paginate (egress budget, §3) and lead with the most-actionable row
  (e.g. defaulters by days overdue, low stock by urgency).

## 6. Forms & data entry (the core of this app)

- One primary action per screen, bottom-anchored, full-width, ≥ 48px.
- Inline, field-level validation with **bilingual** messages mapped from the
  `authedAction` error codes (never raw server text).
- Destructive/locked actions (shift reopen, rent waiver, payroll edit) require a
  reason and are visibly marked super_admin-only.
- Show running totals live (shift income, cash reconciliation variance) so the
  admin sees the number update as they type.

## 7. Accessibility

- Contrast ≥ 4.5:1 for text (glare-tolerant); ≥ 3:1 for large text/UI.
- Every interactive element keyboard-focusable with a visible ring
  (`outline-ring`). Labels tied to inputs. Status conveyed by text + colour.
- Both locales must pass a 360px layout check with no horizontal scroll.
