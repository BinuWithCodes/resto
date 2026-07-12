import { describe, expect, it } from "vitest";
import {
  closingStock,
  ledgerBalance,
  roundQty,
  toBaseQty,
  toPurchaseQty,
  valuationPaise,
  varianceQty,
  varianceValuePaise,
} from "./stock";

describe("unit conversion", () => {
  it("converts purchase units to base units", () => {
    expect(toBaseQty(2, 25)).toBe(50); // 2 bags of 25kg
    expect(toBaseQty(1.5, 12)).toBe(18); // 1.5 cartons of 12
  });
  it("converts base units back to purchase units", () => {
    expect(toPurchaseQty(50, 25)).toBe(2);
    expect(toPurchaseQty(30, 25)).toBe(1.2);
  });
  it("rejects a non-positive conversion factor", () => {
    expect(() => toPurchaseQty(10, 0)).toThrow();
  });
});

describe("closingStock — opening + in − out − waste = closing", () => {
  it("computes a full flow", () => {
    // 100 opening + 50 purchased + 10 transfer-in − 40 consumed − 5 waste
    //   − 8 transfer-out − 2 internal issue = 105
    expect(
      closingStock({
        openingQty: 100,
        purchasedQty: 50,
        transferInQty: 10,
        consumedQty: 40,
        wasteQty: 5,
        transferOutQty: 8,
        internalIssueQty: 2,
      }),
    ).toBe(105);
  });
  it("applies signed adjustments (shrinkage)", () => {
    expect(closingStock({ openingQty: 100, consumedQty: 10, adjustmentQty: -3 })).toBe(87);
  });
  it("avoids float drift and keeps 3 decimals", () => {
    expect(closingStock({ openingQty: 0.1, purchasedQty: 0.2 })).toBe(0.3);
    expect(roundQty(0.1 + 0.2)).toBe(0.3);
  });
});

describe("ledgerBalance", () => {
  it("sums signed deltas onto the opening balance", () => {
    expect(ledgerBalance(100, [50, -40, -5, 10, -8])).toBe(107);
  });
});

describe("valuation & variance", () => {
  it("values stock in integer paise", () => {
    // 12.5 kg × ₹40.00/kg (4000 paise) = ₹500.00
    expect(valuationPaise(12.5, 4000)).toBe(50000);
  });
  it("rounds fractional paise to the nearest integer", () => {
    expect(valuationPaise(0.333, 100)).toBe(33); // 33.3 -> 33
  });
  it("computes count variance and its value", () => {
    expect(varianceQty(48, 50)).toBe(-2); // 2 short
    expect(varianceValuePaise(48, 50, 4000)).toBe(-8000); // −₹80
  });
});
