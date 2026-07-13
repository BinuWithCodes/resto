import { getTranslations } from "next-intl/server";
import { getServerSupabase } from "@/lib/supabase/server";
import { PurchaseForm, type PickableItem } from "@/components/restaurant/purchase-form";

/**
 * Purchase entry (Phase 1). Server component fetches the caller's accessible
 * restaurant location + its active stock items (both RLS-scoped), then hands
 * them to the client form which posts through the createPurchase action.
 */
export default async function PurchasesPage() {
  const t = await getTranslations();
  const supabase = await getServerSupabase();

  const { data: location } = await supabase
    .from("locations")
    .select("id, name")
    .eq("type", "restaurant")
    .eq("active", true)
    .order("name")
    .limit(1)
    .maybeSingle();

  const { data: items } = await supabase
    .from("stock_items")
    .select("id, name, base_unit")
    .eq("active", true)
    .order("name");

  return (
    <section className="max-w-2xl space-y-4 p-4 sm:p-6">
      <div>
        <h1 className="text-xl font-semibold">{t("restaurant.newPurchase")}</h1>
        {location?.name && <p className="text-muted-foreground mt-1 text-sm">{location.name}</p>}
      </div>

      {location ? (
        <PurchaseForm locationId={location.id} items={(items ?? []) as PickableItem[]} />
      ) : (
        <p className="text-muted-foreground text-sm">{t("restaurant.noLocation")}</p>
      )}
    </section>
  );
}
