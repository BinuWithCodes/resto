import { describe, expect, it } from "vitest";
import { addDaysISO, businessDateISO, daysInclusive, daysInMonth, formatDDMMYYYY } from "./dates";

describe("businessDateISO (Asia/Kolkata)", () => {
  it("uses the local calendar date, not UTC", () => {
    // 2026-07-12 19:00 UTC is 2026-07-13 00:30 IST -> business date rolls over
    expect(businessDateISO(new Date("2026-07-12T19:00:00Z"))).toBe("2026-07-13");
    // 2026-07-12 10:00 UTC is 2026-07-12 15:30 IST
    expect(businessDateISO(new Date("2026-07-12T10:00:00Z"))).toBe("2026-07-12");
  });
});

describe("formatDDMMYYYY", () => {
  it("formats ISO as DD/MM/YYYY", () => {
    expect(formatDDMMYYYY("2026-07-12")).toBe("12/07/2026");
  });
  it("rejects a malformed input", () => {
    expect(() => formatDDMMYYYY("12/07/2026")).toThrow();
  });
});

describe("daysInMonth", () => {
  it("handles normal and leap Februaries", () => {
    expect(daysInMonth(2026, 2)).toBe(28);
    expect(daysInMonth(2028, 2)).toBe(29);
    expect(daysInMonth(2026, 7)).toBe(31);
    expect(daysInMonth(2026, 4)).toBe(30);
  });
  it("rejects an out-of-range month", () => {
    expect(() => daysInMonth(2026, 13)).toThrow();
  });
});

describe("daysInclusive & addDaysISO", () => {
  it("counts inclusive days", () => {
    expect(daysInclusive("2026-07-01", "2026-07-01")).toBe(1);
    expect(daysInclusive("2026-07-01", "2026-07-10")).toBe(10);
  });
  it("adds days across a month boundary", () => {
    expect(addDaysISO("2026-07-30", 5)).toBe("2026-08-04");
    expect(addDaysISO("2026-07-10", -9)).toBe("2026-07-01");
  });
});
