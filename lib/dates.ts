/**
 * Date helpers. Timezone is Asia/Kolkata; the "business date" of a shift is the
 * local calendar date. Display format is DD/MM/YYYY (§1.4). ISO dates are
 * "YYYY-MM-DD" strings. Pure + tested.
 */

export const TIME_ZONE = "Asia/Kolkata";

/** The local calendar date (YYYY-MM-DD) for an instant, in Asia/Kolkata. */
export function businessDateISO(instant: Date, timeZone: string = TIME_ZONE): string {
  // en-CA yields YYYY-MM-DD; the timeZone option shifts to local calendar date.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(instant);
}

/** Format an ISO date (YYYY-MM-DD) as DD/MM/YYYY. */
export function formatDDMMYYYY(isoDate: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate);
  if (!match) throw new Error(`Expected YYYY-MM-DD, got: ${isoDate}`);
  const [, y, m, d] = match;
  return `${d}/${m}/${y}`;
}

/** Number of days in a given month (month is 1–12). */
export function daysInMonth(year: number, month: number): number {
  if (month < 1 || month > 12) throw new Error("month must be 1–12");
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** Inclusive day count between two ISO dates (same day = 1). */
export function daysInclusive(fromISO: string, toISO: string): number {
  const from = Date.parse(`${fromISO}T00:00:00Z`);
  const to = Date.parse(`${toISO}T00:00:00Z`);
  if (Number.isNaN(from) || Number.isNaN(to)) throw new Error("invalid ISO date");
  return Math.floor((to - from) / 86_400_000) + 1;
}

/** Add whole days to an ISO date, returning a new ISO date. */
export function addDaysISO(isoDate: string, days: number): string {
  const base = Date.parse(`${isoDate}T00:00:00Z`);
  if (Number.isNaN(base)) throw new Error("invalid ISO date");
  const next = new Date(base + days * 86_400_000);
  return next.toISOString().slice(0, 10);
}
