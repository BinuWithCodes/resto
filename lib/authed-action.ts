import type { ZodType } from "zod";
import { getServerSupabase } from "@/lib/supabase/server";
import { checkRateLimit } from "@/lib/rate-limit";
import { captureException } from "@/lib/observability";

export type AppRole = "super_admin" | "admin";

/**
 * Error codes only — never user-facing strings. The UI maps a code to a
 * localized (en/ta) message via next-intl, so no strings are hardcoded here
 * (§1.4) and no SQL/stack detail ever leaks to the client (§4.5).
 */
export type ActionError =
  | { code: "unauthorized" }
  | { code: "forbidden" }
  | { code: "rate_limited" }
  | { code: "validation"; fields: Record<string, string[]> }
  | { code: "server" };

export type ActionResult<T> = { ok: true; data: T } | { ok: false; error: ActionError };

export interface ActionContext {
  userId: string;
  orgId: string | null;
  role: AppRole;
  supabase: Awaited<ReturnType<typeof getServerSupabase>>;
  /**
   * IDOR defence (§4.5): re-read membership server-side for a specific
   * location before touching its rows. Throws ForbiddenError if no access;
   * the wrapper converts that into a `forbidden` result.
   */
  requireLocationAccess: (locationId: string) => Promise<void>;
}

class ForbiddenError extends Error {}

interface MembershipRow {
  org_id: string;
  location_id: string | null;
  role: AppRole;
}

/**
 * The single Server Action wrapper. Order is law: AUTHORIZE -> VALIDATE ->
 * MUTATE (§4.5). Use it for every action so the discipline can't be forgotten.
 */
export function authedAction<Input, Output>(config: {
  schema: ZodType<Input>;
  requireRole?: AppRole;
  handler: (input: Input, ctx: ActionContext) => Promise<Output>;
}) {
  return async function run(rawInput: unknown): Promise<ActionResult<Output>> {
    try {
      // 1) AUTHORIZE — verify session
      const supabase = await getServerSupabase();
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) return { ok: false, error: { code: "unauthorized" } };

      // role + org are read server-side from memberships; never trusted from the client
      const { data } = await supabase
        .from("memberships")
        .select("org_id, location_id, role")
        .eq("user_id", user.id);
      const rows = (data ?? []) as MembershipRow[];

      const isSuperAdmin = rows.some((m) => m.role === "super_admin" && m.location_id === null);
      const role: AppRole = isSuperAdmin ? "super_admin" : "admin";
      const orgId = rows[0]?.org_id ?? null;

      if (config.requireRole === "super_admin" && !isSuperAdmin) {
        return { ok: false, error: { code: "forbidden" } };
      }

      // rate limit keyed on the user id (Upstash; no-op when unconfigured)
      const { success } = await checkRateLimit(`action:${user.id}`);
      if (!success) return { ok: false, error: { code: "rate_limited" } };

      // 2) VALIDATE
      const parsed = config.schema.safeParse(rawInput);
      if (!parsed.success) {
        const fields: Record<string, string[]> = {};
        for (const issue of parsed.error.issues) {
          const key = issue.path.length ? issue.path.join(".") : "_";
          (fields[key] ??= []).push(issue.message);
        }
        return { ok: false, error: { code: "validation", fields } };
      }

      // context handed to the handler
      const ctx: ActionContext = {
        userId: user.id,
        orgId,
        role,
        supabase,
        requireLocationAccess: async (locationId: string) => {
          if (isSuperAdmin) return;
          if (!rows.some((m) => m.location_id === locationId)) {
            throw new ForbiddenError();
          }
        },
      };

      // 3) MUTATE
      const result = await config.handler(parsed.data, ctx);
      return { ok: true, data: result };
    } catch (err) {
      if (err instanceof ForbiddenError) {
        return { ok: false, error: { code: "forbidden" } };
      }
      captureException(err);
      return { ok: false, error: { code: "server" } };
    }
  };
}
