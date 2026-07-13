import { z } from "zod";

/**
 * Shared input primitives for Server Actions. Money is integer paise (§1.4);
 * quantities are positive numbers (converted to base units before the action,
 * §5 / lib/stock.ts). These schemas are the VALIDATE step of every action;
 * the RPCs behind them re-enforce the same invariants in the database.
 */
export const uuid = z.string().uuid();
export const paise = z.number().int().nonnegative();
export const qty = z.number().positive();

/** ISO calendar date (YYYY-MM-DD) — the business date of a shift/purchase. */
export const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD");

/** Optional offline-sync idempotency envelope (§4.4/§9). */
export const idempotency = {
  device_id: z.string().min(1).max(128).optional(),
  idempotency_key: z.string().min(1).max(128).optional(),
};
