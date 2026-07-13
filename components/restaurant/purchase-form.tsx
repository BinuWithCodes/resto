"use client";

import { useState, useTransition } from "react";
import { useTranslations } from "next-intl";
import { createPurchase } from "@/lib/actions/restaurant";
import { formatINR, rupeesToPaise } from "@/lib/money";

export interface PickableItem {
  id: string;
  name: string;
  base_unit: string;
}

interface Line {
  item_id: string;
  qty: string; // base units, as typed
  rate_rupees: string; // ₹ per base unit, as typed
}

const emptyLine: Line = { item_id: "", qty: "", rate_rupees: "" };

/**
 * Minimal purchase entry: pick items, enter base-unit qty + ₹/unit rate, submit
 * through the createPurchase Server Action (which calls the post_purchase RPC in
 * one transaction). Errors map to the shared bilingual error messages by code.
 */
export function PurchaseForm({ locationId, items }: { locationId: string; items: PickableItem[] }) {
  const t = useTranslations();
  const [lines, setLines] = useState<Line[]>([{ ...emptyLine }]);
  const [status, setStatus] = useState<"paid" | "credit">("paid");
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, startTransition] = useTransition();

  const unitOf = (id: string) => items.find((i) => i.id === id)?.base_unit ?? "";

  const previewPaise = lines.reduce((sum, l) => {
    const q = Number(l.qty);
    const r = Number(l.rate_rupees);
    if (!l.item_id || !isFinite(q) || !isFinite(r) || q <= 0 || r < 0) return sum;
    return sum + Math.round(q * rupeesToPaise(r));
  }, 0);

  function update(i: number, patch: Partial<Line>) {
    setLines((prev) => prev.map((l, idx) => (idx === i ? { ...l, ...patch } : l)));
  }
  function addLine() {
    setLines((prev) => [...prev, { ...emptyLine }]);
  }
  function removeLine(i: number) {
    setLines((prev) => (prev.length === 1 ? prev : prev.filter((_, idx) => idx !== i)));
  }

  function submit() {
    setMessage(null);
    const payloadItems = lines
      .filter((l) => l.item_id && Number(l.qty) > 0)
      .map((l) => ({
        item_id: l.item_id,
        qty: Number(l.qty),
        rate_paise: rupeesToPaise(Number(l.rate_rupees) || 0),
      }));
    if (payloadItems.length === 0) {
      setMessage({ ok: false, text: t("errors.validation") });
      return;
    }
    startTransition(async () => {
      const res = await createPurchase({
        location_id: locationId,
        purchase_date: new Date().toISOString().slice(0, 10),
        payment_status: status,
        items: payloadItems,
      });
      if (res.ok) {
        setMessage({ ok: true, text: t("restaurant.saved") });
        setLines([{ ...emptyLine }]);
      } else {
        setMessage({ ok: false, text: t(`errors.${res.error.code}`) });
      }
    });
  }

  if (items.length === 0) {
    return <p className="text-muted-foreground text-sm">{t("restaurant.noItems")}</p>;
  }

  return (
    <div className="space-y-4">
      <div className="space-y-3">
        {lines.map((line, i) => (
          <div key={i} className="flex flex-wrap items-end gap-2">
            <label className="flex flex-col gap-1 text-xs">
              <span className="text-muted-foreground">{t("restaurant.item")}</span>
              <select
                className="h-9 rounded-md border px-2 text-sm"
                value={line.item_id}
                onChange={(e) => update(i, { item_id: e.target.value })}
              >
                <option value="">{t("restaurant.selectItem")}</option>
                {items.map((it) => (
                  <option key={it.id} value={it.id}>
                    {it.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-xs">
              <span className="text-muted-foreground">
                {t("restaurant.qty")} {unitOf(line.item_id) && `(${unitOf(line.item_id)})`}
              </span>
              <input
                className="h-9 w-24 rounded-md border px-2 text-sm"
                inputMode="decimal"
                value={line.qty}
                onChange={(e) => update(i, { qty: e.target.value })}
              />
            </label>
            <label className="flex flex-col gap-1 text-xs">
              <span className="text-muted-foreground">{t("restaurant.rate")}</span>
              <input
                className="h-9 w-28 rounded-md border px-2 text-sm"
                inputMode="decimal"
                value={line.rate_rupees}
                onChange={(e) => update(i, { rate_rupees: e.target.value })}
              />
            </label>
            <button
              type="button"
              onClick={() => removeLine(i)}
              className="text-muted-foreground hover:text-foreground h-9 px-2 text-sm"
              aria-label={t("restaurant.removeLine")}
            >
              ✕
            </button>
          </div>
        ))}
      </div>

      <button
        type="button"
        onClick={addLine}
        className="text-sm font-medium text-blue-600 hover:underline"
      >
        + {t("restaurant.addLine")}
      </button>

      <div className="flex flex-wrap items-center gap-4 border-t pt-4">
        <label className="flex items-center gap-2 text-sm">
          <span className="text-muted-foreground">{t("restaurant.paymentStatus")}</span>
          <select
            className="h-9 rounded-md border px-2 text-sm"
            value={status}
            onChange={(e) => setStatus(e.target.value as "paid" | "credit")}
          >
            <option value="paid">{t("restaurant.paid")}</option>
            <option value="credit">{t("restaurant.credit")}</option>
          </select>
        </label>
        <span className="text-sm">
          {t("restaurant.total")}: <strong>{formatINR(previewPaise)}</strong>
        </span>
        <button
          type="button"
          onClick={submit}
          disabled={pending}
          className="ml-auto h-9 rounded-md bg-blue-600 px-4 text-sm font-medium text-white disabled:opacity-50"
        >
          {t("restaurant.save")}
        </button>
      </div>

      {message && (
        <p className={`text-sm ${message.ok ? "text-green-600" : "text-red-600"}`}>
          {message.text}
        </p>
      )}
    </div>
  );
}
