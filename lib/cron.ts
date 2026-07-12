import { serverEnv } from "@/lib/env";

/**
 * Verify a cron request carries the shared secret in the Authorization header
 * (`Bearer <CRON_SECRET>`). Used by every /api/cron/* route — Vercel cron and
 * cron-job.org both send this header (§2). Returns false when unset/mismatched.
 */
export function isAuthorizedCron(request: Request): boolean {
  const header = request.headers.get("authorization");
  if (!header) return false;
  const expected = `Bearer ${serverEnv("CRON_SECRET")}`;
  return header === expected;
}
