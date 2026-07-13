import { getTranslations } from "next-intl/server";
import { getServerSupabase } from "@/lib/supabase/server";
import { RentPaymentForm, type PickableTenant } from "@/components/hostel/rent-payment-form";

/**
 * Rent collection (Phase 2). Lists the caller's active tenants (RLS-scoped) and
 * records a payment through the record_rent_payment RPC (oldest-first allocation).
 */
export default async function RentPage() {
  const t = await getTranslations();
  const supabase = await getServerSupabase();

  const { data: tenants } = await supabase
    .from("tenants")
    .select("id, name")
    .eq("status", "active")
    .order("name");

  return (
    <section className="max-w-2xl space-y-4 p-4 sm:p-6">
      <h1 className="text-xl font-semibold">{t("hostel.recordPayment")}</h1>
      <RentPaymentForm tenants={(tenants ?? []) as PickableTenant[]} />
    </section>
  );
}
