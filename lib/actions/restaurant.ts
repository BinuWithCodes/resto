"use server";

import { z } from "zod";
import { authedAction } from "@/lib/authed-action";
import { uuid, paise, qty, isoDate, idempotency } from "@/lib/actions/common";

/**
 * Restaurant Server Actions — thin, authorized wrappers over the transactional
 * RPCs (§4.4). Each: requireLocationAccess (IDOR, §4.5) where a location is in
 * the input, then a single supabase.rpc() call. The RPC owns the transaction,
 * the ledger writes, and the integrity checks; a Postgres error is thrown so the
 * authedAction wrapper reports `server` (details go to Sentry, never the client).
 */

const purchaseLine = z.object({
  item_id: uuid,
  qty, // base units
  rate_paise: paise, // per base unit
});

export const createPurchase = authedAction({
  schema: z.object({
    location_id: uuid,
    supplier_id: uuid.nullable().optional(),
    purchase_date: isoDate,
    payment_status: z.enum(["paid", "credit"]),
    items: z.array(purchaseLine).min(1),
    shift_session_id: uuid.nullable().optional(),
    notes: z.string().max(500).nullable().optional(),
    ...idempotency,
  }),
  handler: async (input, ctx) => {
    await ctx.requireLocationAccess(input.location_id);
    const { data, error } = await ctx.supabase.rpc("post_purchase", {
      p_location_id: input.location_id,
      p_supplier_id: input.supplier_id ?? null,
      p_purchase_date: input.purchase_date,
      p_payment_status: input.payment_status,
      p_items: input.items,
      p_shift_session_id: input.shift_session_id ?? null,
      p_notes: input.notes ?? null,
      p_device_id: input.device_id ?? null,
      p_idempotency_key: input.idempotency_key ?? null,
    });
    if (error) throw error;
    return data;
  },
});

export const postConsumption = authedAction({
  schema: z.object({
    location_id: uuid,
    shift_session_id: uuid.nullable().optional(),
    items: z.array(z.object({ item_id: uuid, qty })).min(1),
    note: z.string().max(500).nullable().optional(),
    ...idempotency,
  }),
  handler: async (input, ctx) => {
    await ctx.requireLocationAccess(input.location_id);
    const { data, error } = await ctx.supabase.rpc("post_consumption", {
      p_location_id: input.location_id,
      p_shift_session_id: input.shift_session_id ?? null,
      p_items: input.items,
      p_note: input.note ?? null,
      p_device_id: input.device_id ?? null,
      p_idempotency_key: input.idempotency_key ?? null,
    });
    if (error) throw error;
    return data;
  },
});

export const postWaste = authedAction({
  schema: z.object({
    location_id: uuid,
    shift_session_id: uuid.nullable().optional(),
    items: z
      .array(
        z.object({
          item_id: uuid,
          qty,
          reason_code: z.enum([
            "expired",
            "spoiled",
            "overcooked",
            "customer_return",
            "damaged",
            "other",
          ]),
          cost_paise: paise.nullable().optional(),
        }),
      )
      .min(1),
    ...idempotency,
  }),
  handler: async (input, ctx) => {
    await ctx.requireLocationAccess(input.location_id);
    const { data, error } = await ctx.supabase.rpc("post_waste", {
      p_location_id: input.location_id,
      p_shift_session_id: input.shift_session_id ?? null,
      p_items: input.items,
      p_device_id: input.device_id ?? null,
      p_idempotency_key: input.idempotency_key ?? null,
    });
    if (error) throw error;
    return data;
  },
});

export const closeShift = authedAction({
  schema: z.object({
    session_id: uuid,
    actual_cash_paise: paise,
    variance_reason: z.string().max(500).nullable().optional(),
    handover_note: z.string().max(1000).nullable().optional(),
  }),
  handler: async (input, ctx) => {
    // Access is enforced by the RPC's RLS (an out-of-scope session reads as
    // not-found); the session's location_id is not in the client input.
    const { data, error } = await ctx.supabase.rpc("close_shift", {
      p_session_id: input.session_id,
      p_actual_cash: input.actual_cash_paise,
      p_variance_reason: input.variance_reason ?? null,
      p_handover_note: input.handover_note ?? null,
    });
    if (error) throw error;
    return data;
  },
});

export const lockShift = authedAction({
  schema: z.object({ session_id: uuid }),
  handler: async (input, ctx) => {
    const { data, error } = await ctx.supabase.rpc("lock_shift", {
      p_session_id: input.session_id,
    });
    if (error) throw error;
    return data;
  },
});

export const finalizeStockCount = authedAction({
  schema: z.object({ count_id: uuid }),
  handler: async (input, ctx) => {
    const { data, error } = await ctx.supabase.rpc("finalize_stock_count", {
      p_count_id: input.count_id,
    });
    if (error) throw error;
    return data;
  },
});
