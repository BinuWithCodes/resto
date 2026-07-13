import { getTranslations } from "next-intl/server";
import { getServerSupabase } from "@/lib/supabase/server";
import { PayrollPanel, type DraftRun } from "@/components/staff/payroll-panel";

/**
 * Payroll (Phase 3). Lists draft runs (RLS-scoped) and drives run/approve via
 * the run_payroll / approve_payroll RPCs. Approval is super_admin-gated in the DB.
 */
export default async function PayrollPage() {
  const t = await getTranslations();
  const supabase = await getServerSupabase();

  const { data: runs } = await supabase
    .from("payroll_runs")
    .select("id, period")
    .eq("status", "draft")
    .order("period", { ascending: false });

  return (
    <section className="max-w-2xl space-y-4 p-4 sm:p-6">
      <h1 className="text-xl font-semibold">{t("staff.payroll")}</h1>
      <PayrollPanel draftRuns={(runs ?? []) as DraftRun[]} />
    </section>
  );
}
