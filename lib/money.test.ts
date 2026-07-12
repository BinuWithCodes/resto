import { describe, expect, it } from "vitest";
import {
  allocateOldestFirst,
  depositRefundPaise,
  formatINR,
  lateFeePaise,
  paiseToRupees,
  payrollNetPaise,
  proRataPaise,
  rupeesToPaise,
  variancePaise,
} from "./money";

describe("rupeesToPaise / paiseToRupees", () => {
  it("converts rupees to integer paise", () => {
    expect(rupeesToPaise(1)).toBe(100);
    expect(rupeesToPaise(1234.56)).toBe(123456);
    expect(rupeesToPaise(0.1)).toBe(10);
  });
  it("rounds float artefacts to the nearest paise", () => {
    expect(rupeesToPaise(19.99)).toBe(1999);
    expect(rupeesToPaise(0.005)).toBe(1); // 0.5 paise rounds up... 0.005*100=0.5 -> 1
  });
  it("round-trips", () => {
    expect(paiseToRupees(123456)).toBe(1234.56);
  });
});

describe("formatINR — Indian digit grouping", () => {
  it("formats zero and small amounts", () => {
    expect(formatINR(0)).toBe("₹0.00");
    expect(formatINR(99)).toBe("₹0.99");
    expect(formatINR(100)).toBe("₹1.00");
  });
  it("groups the Indian way (lakh/crore)", () => {
    expect(formatINR(123456_78)).toBe("₹1,23,456.78");
    expect(formatINR(1000000_00)).toBe("₹10,00,000.00");
    expect(formatINR(10000000_00)).toBe("₹1,00,00,000.00");
  });
  it("handles negatives and the no-symbol option", () => {
    expect(formatINR(-50000)).toBe("-₹500.00");
    expect(formatINR(123456_78, { withSymbol: false })).toBe("1,23,456.78");
  });
});

describe("proRataPaise", () => {
  it("prorates a partial month", () => {
    // ₹9000/mo, 10 of 30 days
    expect(proRataPaise(900000, 10, 30)).toBe(300000);
  });
  it("clamps to the month and rounds", () => {
    expect(proRataPaise(900000, 40, 30)).toBe(900000);
    expect(proRataPaise(900000, 0, 30)).toBe(0);
    expect(proRataPaise(1000000, 1, 31)).toBe(32258); // 10000_00/31
  });
  it("rejects a non-positive month length", () => {
    expect(() => proRataPaise(100, 1, 0)).toThrow();
  });
});

describe("lateFeePaise", () => {
  it("applies a flat fee after grace", () => {
    const rule = { type: "flat", amountPaise: 10000, graceDays: 3 } as const;
    expect(lateFeePaise(rule, 2)).toBe(0);
    expect(lateFeePaise(rule, 3)).toBe(0);
    expect(lateFeePaise(rule, 4)).toBe(10000);
  });
  it("applies a per-day fee with a cap", () => {
    const rule = { type: "per_day", amountPaise: 5000, capPaise: 20000 } as const;
    expect(lateFeePaise(rule, 1)).toBe(5000);
    expect(lateFeePaise(rule, 3)).toBe(15000);
    expect(lateFeePaise(rule, 10)).toBe(20000); // capped
  });
});

describe("allocateOldestFirst", () => {
  it("clears oldest invoices first and returns the advance", () => {
    const res = allocateOldestFirst(150000, [
      { id: "a", balancePaise: 100000 },
      { id: "b", balancePaise: 80000 },
    ]);
    expect(res.allocations).toEqual([
      { invoiceId: "a", appliedPaise: 100000 },
      { invoiceId: "b", appliedPaise: 50000 },
    ]);
    expect(res.unappliedPaise).toBe(0);
  });
  it("returns overpayment as unapplied advance", () => {
    const res = allocateOldestFirst(250000, [{ id: "a", balancePaise: 100000 }]);
    expect(res.allocations).toEqual([{ invoiceId: "a", appliedPaise: 100000 }]);
    expect(res.unappliedPaise).toBe(150000);
  });
  it("handles a partial payment", () => {
    const res = allocateOldestFirst(30000, [{ id: "a", balancePaise: 100000 }]);
    expect(res.allocations).toEqual([{ invoiceId: "a", appliedPaise: 30000 }]);
    expect(res.unappliedPaise).toBe(0);
  });
});

describe("payrollNetPaise", () => {
  it("computes net = salary − unpaid leave − advance + OT + bonus", () => {
    const r = payrollNetPaise({
      monthlySalaryPaise: 3000000, // ₹30,000
      workingDays: 30,
      unpaidLeaveDays: 2,
      advanceDeductionPaise: 500000, // ₹5,000
      otPaise: 100000, // ₹1,000
      bonusPaise: 200000, // ₹2,000
    });
    expect(r.perDayPaise).toBe(100000); // ₹1,000/day
    expect(r.leaveDeductionPaise).toBe(200000); // 2 days
    // 3,000,000 − 200,000 − 500,000 + 100,000 + 200,000 = 2,600,000
    expect(r.netPaise).toBe(2600000);
  });
  it("rejects zero working days", () => {
    expect(() =>
      payrollNetPaise({
        monthlySalaryPaise: 100,
        workingDays: 0,
        unpaidLeaveDays: 0,
        advanceDeductionPaise: 0,
        otPaise: 0,
        bonusPaise: 0,
      }),
    ).toThrow();
  });
});

describe("depositRefundPaise & variancePaise", () => {
  it("settles a deposit", () => {
    expect(
      depositRefundPaise({
        depositPaise: 1000000,
        deductionsPaise: 200000,
        outstandingPaise: 50000,
      }),
    ).toBe(750000);
  });
  it("can go negative when the tenant owes more than the deposit", () => {
    expect(
      depositRefundPaise({ depositPaise: 100000, deductionsPaise: 0, outstandingPaise: 200000 }),
    ).toBe(-100000);
  });
  it("computes cash variance (actual − expected)", () => {
    expect(variancePaise(500000, 480000)).toBe(-20000); // short by ₹200
    expect(variancePaise(500000, 500000)).toBe(0);
  });
});
