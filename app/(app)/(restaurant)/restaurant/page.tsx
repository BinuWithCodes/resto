import { getTranslations } from "next-intl/server";

export default async function RestaurantPage() {
  const t = await getTranslations();
  return (
    <section className="p-4 sm:p-6">
      <h1 className="text-xl font-semibold">{t("nav.restaurant")}</h1>
      <p className="text-muted-foreground mt-2 text-sm">{t("common.phasePlaceholder")}</p>
    </section>
  );
}
