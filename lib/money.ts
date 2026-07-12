/**
 * Money engine. ALL money is integer paise (§1.4) — never floats, never rupees
 * with decimals in storage. Rupees appear only at the UI edge via formatINR /
 * rupeesToPaise. Every function here is pure and unit-tested.
 */

/** Convert a rupee amount (may have up to 2 decimals) to integer paise. */
export function rupeesToPaise(rupees: number): number {
  return Math.round(rupees * 100);
}

/** Convert integer paise to a rupee number (for input fields only, not storage). */
export function paiseToRupees(paise: number): number {
  return paise / 100;
}

/**
 * Format integer paise as INR with Indian digit grouping (₹1,23,456.78).
 * Implemented manually (not via Intl) so output is deterministic across ICU
 * versions. Negative amounts render as -₹...; paise are always shown.
 */
export function formatINR(paise: number, options?: { withSymbol?: boolean }): string {
  const withSymbol = options?.withSymbol ?? true;
  const negative = paise < 0;
  const abs = Math.abs(Math.trunc(paise));
  const rupees = Math.floor(abs / 100);
  const paisePart = abs % 100;

  const digits = String(rupees);
  let grouped: string;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    const last3 = digits.slice(-3);
    const rest = digits.slice(0, -3);
    const pairs = rest.replace(/\B(?=(\d{2})+(?!\d))/g, ",");
    grouped = `${pairs},${last3}`;
  }

  const body = `${grouped}.${String(paisePart).padStart(2, "0")}`;
  return `${negative ? "-" : ""}${withSymbol ? "₹" : ""}${body}`;
}

/**
 * Pro-rata a monthly amount for a partial month (mid-month join/leave).
 * occupiedDays and daysInMonth are whole days; result rounds to nearest paise.
 */
export function proRataPaise(
  monthlyPaise: number,
  occupiedDays: number,
  daysInMonth: number,
): number {
  if (daysInMonth <= 0) throw new Error("daysInMonth must be > 0");
  const clampedDays = Math.max(0, Math.min(occupiedDays, daysInMonth));
  return Math.round((monthlyPaise * clampedDays) / daysInMonth);
}

export type LateFeeRule =
  | { type: "flat"; amountPaise: number; graceDays?: number }
  | { type: "per_day"; amountPaise: number; graceDays?: number; capPaise?: number };

/** Late fee for a number of days overdue, honouring a grace period and cap. */
export function lateFeePaise(rule: LateFeeRule, daysOverdue: number): number {
  const grace = rule.graceDays ?? 0;
  const chargeableDays = Math.max(0, daysOverdue - grace);
  if (chargeableDays <= 0) return 0;
  if (rule.type === "flat") return rule.amountPaise;
  const raw = rule.amountPaise * chargeableDays;
  return rule.capPaise != null ? Math.min(raw, rule.capPaise) : raw;
}

export interface OpenInvoice {
  id: string;
  balancePaise: number;
}
export interface Allocation {
  invoiceId: string;
  appliedPaise: number;
}
export interface AllocationResult {
  allocations: Allocation[];
  /** Overpayment left after clearing all invoices (advance/credit). */
  unappliedPaise: number;
}

/**
 * Allocate a payment to invoices oldest-first (the array order IS the age
 * order). Fully clears earlier invoices before touching later ones; any
 * remainder is returned as unapplied (advance).
 */
export function allocateOldestFirst(
  paymentPaise: number,
  invoices: OpenInvoice[],
): AllocationResult {
  if (paymentPaise < 0) throw new Error("payment must be >= 0");
  let remaining = paymentPaise;
  const allocations: Allocation[] = [];
  for (const invoice of invoices) {
    if (remaining <= 0) break;
    const applied = Math.min(remaining, Math.max(0, invoice.balancePaise));
    if (applied > 0) {
      allocations.push({ invoiceId: invoice.id, appliedPaise: applied });
      remaining -= applied;
    }
  }
  return { allocations, unappliedPaise: remaining };
}

export interface PayrollInput {
  monthlySalaryPaise: number;
  workingDays: number;
  unpaidLeaveDays: number;
  advanceDeductionPaise: number;
  otPaise: number;
  bonusPaise: number;
}

/** Net payable = salary − unpaid-leave − advance + OT + bonus (§6 staff, §8). */
export function payrollNetPaise(input: PayrollInput): {
  perDayPaise: number;
  leaveDeductionPaise: number;
  netPaise: number;
} {
  if (input.workingDays <= 0) throw new Error("workingDays must be > 0");
  const perDayPaise = Math.round(input.monthlySalaryPaise / input.workingDays);
  const leaveDeductionPaise = perDayPaise * Math.max(0, input.unpaidLeaveDays);
  const netPaise =
    input.monthlySalaryPaise -
    leaveDeductionPaise -
    input.advanceDeductionPaise +
    input.otPaise +
    input.bonusPaise;
  return { perDayPaise, leaveDeductionPaise, netPaise };
}

/** Move-out deposit settlement. Positive refund = owed to tenant; negative = tenant owes. */
export function depositRefundPaise(input: {
  depositPaise: number;
  deductionsPaise: number;
  outstandingPaise: number;
}): number {
  return input.depositPaise - input.deductionsPaise - input.outstandingPaise;
}

/** Cash reconciliation variance = actual − expected (negative = short). */
export function variancePaise(expectedPaise: number, actualPaise: number): number {
  return actualPaise - expectedPaise;
}
