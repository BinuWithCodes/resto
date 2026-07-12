/**
 * Stock math. Quantities are numeric(12,3) (kg/L need 3 decimals), so every
 * result is rounded to 3 decimals to avoid float drift. Rates are integer paise
 * per base unit; valuations return integer paise. All functions pure + tested.
 *
 * The append-only stock_movements ledger is the source of truth (§4.4); these
 * helpers mirror its arithmetic for previews and reconciliation checks.
 */

/** Round a quantity to 3 decimal places (the DB precision). */
export function roundQty(qty: number): number {
  return Math.round(qty * 1000) / 1000;
}

/** Purchase unit -> base unit (e.g. 2 bags × 25 = 50 kg). */
export function toBaseQty(purchaseQty: number, conversionFactor: number): number {
  return roundQty(purchaseQty * conversionFactor);
}

/** Base unit -> purchase unit (e.g. 50 kg ÷ 25 = 2 bags). */
export function toPurchaseQty(baseQty: number, conversionFactor: number): number {
  if (conversionFactor <= 0) throw new Error("conversionFactor must be > 0");
  return roundQty(baseQty / conversionFactor);
}

export interface StockFlow {
  openingQty: number;
  purchasedQty?: number;
  transferInQty?: number;
  consumedQty?: number;
  wasteQty?: number;
  transferOutQty?: number;
  internalIssueQty?: number;
  purchaseReturnQty?: number;
  /** Signed correction from a physical count (+ excess, − shrinkage). */
  adjustmentQty?: number;
}

/**
 * Closing stock identity: opening + in − out − waste (+/− adjustment) = closing.
 * IN  = purchases + transfer-in.  OUT = consumption + waste + transfer-out +
 * internal issue + purchase return.
 */
export function closingStock(flow: StockFlow): number {
  const inQty = (flow.purchasedQty ?? 0) + (flow.transferInQty ?? 0);
  const outQty =
    (flow.consumedQty ?? 0) +
    (flow.wasteQty ?? 0) +
    (flow.transferOutQty ?? 0) +
    (flow.internalIssueQty ?? 0) +
    (flow.purchaseReturnQty ?? 0);
  return roundQty(flow.openingQty + inQty - outQty + (flow.adjustmentQty ?? 0));
}

/** Current balance = opening + Σ signed movement deltas (the ledger sum). */
export function ledgerBalance(openingQty: number, deltas: number[]): number {
  return roundQty(deltas.reduce((sum, d) => sum + d, openingQty));
}

/** Valuation in integer paise: qty × rate (paise per base unit). */
export function valuationPaise(qty: number, ratePaise: number): number {
  return Math.round(qty * ratePaise);
}

/** Count variance: counted − system (negative = shrinkage). */
export function varianceQty(countedQty: number, systemQty: number): number {
  return roundQty(countedQty - systemQty);
}

/** Value of a count variance in integer paise. */
export function varianceValuePaise(
  countedQty: number,
  systemQty: number,
  ratePaise: number,
): number {
  return valuationPaise(varianceQty(countedQty, systemQty), ratePaise);
}
