"use server";

import { z } from "zod";
import { authedAction } from "@/lib/authed-action";
import { uuid, paise, isoDate, idempotency } from "@/lib/actions/common";

/**
 * Hostel Server Actions over the transactional RPCs (§4.4). record_rent_payment
 * allocates oldest-first inside the DB; settle_moveout is super_admin-gated by a
 * trigger (the wrapper's requireRole adds a fast client-visible guard, and the
 * trigger remains the source of truth).
 */

export const recordRentPayment = authedAction({
  schema: z.object({
    tenant_id: uuid,
    amount_paise: paise,
    paid_date: isoDate,
    mode: z.enum(["upi", "cash", "bank"]),
    ...idempotency,
  }),
  handler: async (input, ctx) => {
    const { data, error } = await ctx.supabase.rpc("record_rent_payment", {
      p_tenant_id: input.tenant_id,
      p_amount_paise: input.amount_paise,
      p_paid_date: input.paid_date,
      p_mode: input.mode,
      p_device_id: input.device_id ?? null,
      p_idempotency_key: input.idempotency_key ?? null,
    });
    if (error) throw error;
    return data;
  },
});

export const settleMoveout = authedAction({
  requireRole: "super_admin",
  schema: z.object({ moveout_id: uuid }),
  handler: async (input, ctx) => {
    const { data, error } = await ctx.supabase.rpc("settle_moveout", {
      p_moveout_id: input.moveout_id,
    });
    if (error) throw error;
    return data;
  },
});
