"use server";

import { z } from "zod";
import { authedAction } from "@/lib/authed-action";
import { uuid } from "@/lib/actions/common";

/**
 * Staff Server Actions over the payroll RPCs (§4.4). run_payroll builds a draft
 * any admin may prepare; approve_payroll is super_admin-gated by a trigger (the
 * requireRole guard mirrors that in the app layer for a fast, clear rejection).
 */

export const runPayroll = authedAction({
  schema: z.object({
    period: z.string().regex(/^\d{4}-\d{2}$/, "expected YYYY-MM"),
    working_days: z.number().int().min(1).max(31),
    scope: z.string().max(64).default("all"),
  }),
  handler: async (input, ctx) => {
    const { data, error } = await ctx.supabase.rpc("run_payroll", {
      p_period: input.period,
      p_working_days: input.working_days,
      p_scope: input.scope,
    });
    if (error) throw error;
    return data;
  },
});

export const approvePayroll = authedAction({
  requireRole: "super_admin",
  schema: z.object({ run_id: uuid }),
  handler: async (input, ctx) => {
    const { data, error } = await ctx.supabase.rpc("approve_payroll", {
      p_run_id: input.run_id,
    });
    if (error) throw error;
    return data;
  },
});
