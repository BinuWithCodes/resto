import { getTranslations } from "next-intl/server";

// Owner dashboard home. Renders at "/" (route groups add no URL segment).
export default async function DashboardHome() {
  const t = await getTranslations();
  return (
    <section className="p-4 sm:p-6">
      <h1 className="text-xl font-semibold">{t("nav.dashboard")}</h1>
      <p className="text-muted-foreground mt-2 text-sm">{t("common.phasePlaceholder")}</p>
    </section>
  );
}
