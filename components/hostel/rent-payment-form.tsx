"use client";

import { useState, useTransition } from "react";
import { useTranslations } from "next-intl";
import { recordRentPayment } from "@/lib/actions/hostel";
import { rupeesToPaise } from "@/lib/money";

export interface PickableTenant {
  id: string;
  name: string;
}

/**
 * Record a rent payment against a tenant. The amount is applied oldest-invoice
 * first inside the record_rent_payment RPC; the form only collects tenant,
 * amount, and mode, then reports success or a bilingual error by code.
 */
export function RentPaymentForm({ tenants }: { tenants: PickableTenant[] }) {
  const t = useTranslations();
  const [tenantId, setTenantId] = useState("");
  const [amount, setAmount] = useState("");
  const [mode, setMode] = useState<"upi" | "cash" | "bank">("upi");
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, startTransition] = useTransition();

  function submit() {
    setMessage(null);
    const rupees = Number(amount);
    if (!tenantId || !isFinite(rupees) || rupees <= 0) {
      setMessage({ ok: false, text: t("errors.validation") });
      return;
    }
    startTransition(async () => {
      const res = await recordRentPayment({
        tenant_id: tenantId,
        amount_paise: rupeesToPaise(rupees),
        paid_date: new Date().toISOString().slice(0, 10),
        mode,
      });
      setMessage(
        res.ok
          ? { ok: true, text: t("hostel.paymentSaved") }
          : { ok: false, text: t(`errors.${res.error.code}`) },
      );
      if (res.ok) setAmount("");
    });
  }

  if (tenants.length === 0) {
    return <p className="text-muted-foreground text-sm">{t("hostel.noTenants")}</p>;
  }

  return (
    <div className="max-w-md space-y-3">
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-muted-foreground">{t("hostel.tenant")}</span>
        <select
          className="h-9 rounded-md border px-2 text-sm"
          value={tenantId}
          onChange={(e) => setTenantId(e.target.value)}
        >
          <option value="">{t("hostel.selectTenant")}</option>
          {tenants.map((tn) => (
            <option key={tn.id} value={tn.id}>
              {tn.name}
            </option>
          ))}
        </select>
      </label>

      <div className="flex gap-3">
        <label className="flex flex-1 flex-col gap-1 text-sm">
          <span className="text-muted-foreground">{t("hostel.amount")}</span>
          <input
            className="h-9 rounded-md border px-2 text-sm"
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted-foreground">{t("hostel.mode")}</span>
          <select
            className="h-9 rounded-md border px-2 text-sm"
            value={mode}
            onChange={(e) => setMode(e.target.value as "upi" | "cash" | "bank")}
          >
            <option value="upi">{t("hostel.upi")}</option>
            <option value="cash">{t("hostel.cash")}</option>
            <option value="bank">{t("hostel.bank")}</option>
          </select>
        </label>
      </div>

      <button
        type="button"
        onClick={submit}
        disabled={pending}
        className="h-9 rounded-md bg-blue-600 px-4 text-sm font-medium text-white disabled:opacity-50"
      >
        {t("hostel.recordPayment")}
      </button>

      {message && (
        <p className={`text-sm ${message.ok ? "text-green-600" : "text-red-600"}`}>
          {message.text}
        </p>
      )}
    </div>
  );
}
