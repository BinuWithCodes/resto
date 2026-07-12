import { beforeEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";

// Mutable state the mocks read from, controlled per test.
const state = vi.hoisted(() => ({
  user: null as { id: string } | null,
  memberships: [] as Array<{ org_id: string; location_id: string | null; role: string }>,
  rateOk: true,
}));

vi.mock("@/lib/supabase/server", () => ({
  getServerSupabase: async () => ({
    auth: { getUser: async () => ({ data: { user: state.user } }) },
    from: () => ({
      select: () => ({
        eq: async () => ({ data: state.memberships }),
      }),
    }),
  }),
}));
vi.mock("@/lib/rate-limit", () => ({
  checkRateLimit: async () => ({ success: state.rateOk }),
}));
vi.mock("@/lib/observability", () => ({ captureException: vi.fn() }));

import { authedAction } from "./authed-action";

const schema = z.object({ name: z.string().min(1) });

beforeEach(() => {
  state.user = { id: "u1" };
  state.memberships = [{ org_id: "o1", location_id: "locA", role: "admin" }];
  state.rateOk = true;
});

describe("authedAction", () => {
  it("rejects an unauthenticated caller", async () => {
    state.user = null;
    const run = authedAction({ schema, handler: async () => "ok" });
    const res = await run({ name: "x" });
    expect(res).toEqual({ ok: false, error: { code: "unauthorized" } });
  });

  it("enforces requireRole: super_admin", async () => {
    const run = authedAction({ schema, requireRole: "super_admin", handler: async () => "ok" });
    const res = await run({ name: "x" });
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.error.code).toBe("forbidden");
  });

  it("allows a super_admin through the role gate", async () => {
    state.memberships = [{ org_id: "o1", location_id: null, role: "super_admin" }];
    const run = authedAction({
      schema,
      requireRole: "super_admin",
      handler: async (input) => `hi ${input.name}`,
    });
    const res = await run({ name: "owner" });
    expect(res).toEqual({ ok: true, data: "hi owner" });
  });

  it("returns flattened field errors on invalid input", async () => {
    const run = authedAction({ schema, handler: async () => "ok" });
    const res = await run({ name: "" });
    expect(res.ok).toBe(false);
    if (!res.ok && res.error.code === "validation") {
      expect(res.error.fields.name?.length).toBeGreaterThan(0);
    } else {
      throw new Error("expected validation error");
    }
  });

  it("trips the rate limiter", async () => {
    state.rateOk = false;
    const run = authedAction({ schema, handler: async () => "ok" });
    const res = await run({ name: "x" });
    expect(res).toEqual({ ok: false, error: { code: "rate_limited" } });
  });

  it("runs the handler on the happy path with context", async () => {
    const run = authedAction({
      schema,
      handler: async (input, ctx) => ({ name: input.name, role: ctx.role, org: ctx.orgId }),
    });
    const res = await run({ name: "shift-1" });
    expect(res).toEqual({ ok: true, data: { name: "shift-1", role: "admin", org: "o1" } });
  });

  it("blocks cross-location access via requireLocationAccess (IDOR defence)", async () => {
    const run = authedAction({
      schema,
      handler: async (_input, ctx) => {
        await ctx.requireLocationAccess("locB"); // admin only has locA
        return "should not reach";
      },
    });
    const res = await run({ name: "x" });
    expect(res).toEqual({ ok: false, error: { code: "forbidden" } });
  });

  it("permits access to the caller's own location", async () => {
    const run = authedAction({
      schema,
      handler: async (_input, ctx) => {
        await ctx.requireLocationAccess("locA");
        return "reached";
      },
    });
    const res = await run({ name: "x" });
    expect(res).toEqual({ ok: true, data: "reached" });
  });
});
