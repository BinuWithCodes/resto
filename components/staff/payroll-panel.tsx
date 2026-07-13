"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { runPayroll, approvePayroll } from "@/lib/actions/staff";

export interface DraftRun {
  id: string;
  period: string;
}

/**
 * Payroll (Phase 3): run a draft for a period (any admin) and approve a draft
 * (super_admin only — the action's requireRole + the DB trigger both enforce it).
 * The run/approve RPCs own the math and locking; this panel is thin.
 */
export function PayrollPanel({ draftRuns }: { draftRuns: DraftRun[] }) {
  const t = useTranslations();
  const router = useRouter();
  const [period, setPeriod] = useState(new Date().toISOString().slice(0, 7));
  const [workingDays, setWorkingDays] = useState("26");
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, startTransition] = useTransition();

  function run() {
    setMessage(null);
    const days = Number(workingDays);
    if (!/^\d{4}-\d{2}$/.test(period) || !Number.isInteger(days) || days < 1) {
      setMessage({ ok: false, text: t("errors.validation") });
      return;
    }
    startTransition(async () => {
      const res = await runPayroll({ period, working_days: days, scope: "all" });
      setMessage(
        res.ok
          ? { ok: true, text: t("staff.runCreated") }
          : { ok: false, text: t(`errors.${res.error.code}`) },
      );
      if (res.ok) router.refresh();
    });
  }

  function approve(runId: string) {
    setMessage(null);
    startTransition(async () => {
      const res = await approvePayroll({ run_id: runId });
      setMessage(
        res.ok
          ? { ok: true, text: t("staff.approved") }
          : { ok: false, text: t(`errors.${res.error.code}`) },
      );
      if (res.ok) router.refresh();
    });
  }

  return (
    <div className="max-w-xl space-y-5">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted-foreground">{t("staff.period")}</span>
          <input
            className="h-9 rounded-md border px-2 text-sm"
            type="month"
            value={period}
            onChange={(e) => setPeriod(e.target.value)}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted-foreground">{t("staff.workingDays")}</span>
          <input
            className="h-9 w-24 rounded-md border px-2 text-sm"
            inputMode="numeric"
            value={workingDays}
            onChange={(e) => setWorkingDays(e.target.value)}
          />
        </label>
        <button
          type="button"
          onClick={run}
          disabled={pending}
          className="h-9 rounded-md bg-blue-600 px-4 text-sm font-medium text-white disabled:opacity-50"
        >
          {t("staff.runPayroll")}
        </button>
      </div>

      <div className="space-y-2">
        <h2 className="text-sm font-medium">{t("staff.draftRuns")}</h2>
        {draftRuns.length === 0 ? (
          <p className="text-muted-foreground text-sm">{t("staff.noDrafts")}</p>
        ) : (
          <ul className="divide-y rounded-md border">
            {draftRuns.map((r) => (
              <li key={r.id} className="flex items-center justify-between px-3 py-2 text-sm">
                <span>{r.period}</span>
                <button
                  type="button"
                  onClick={() => approve(r.id)}
                  disabled={pending}
                  className="rounded-md border px-3 py-1 text-xs font-medium hover:bg-neutral-50 disabled:opacity-50"
                >
                  {t("staff.approve")}
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {message && (
        <p className={`text-sm ${message.ok ? "text-green-600" : "text-red-600"}`}>
          {message.text}
        </p>
      )}
    </div>
  );
}
