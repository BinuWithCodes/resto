import { getTranslations } from "next-intl/server";

// super_admin only — nav omits it for admins; server-side gating added in 0.7.
export default async function SettingsPage() {
  const t = await getTranslations();
  return (
    <section className="p-4 sm:p-6">
      <h1 className="text-xl font-semibold">{t("nav.settings")}</h1>
      <p className="text-muted-foreground mt-2 text-sm">{t("common.phasePlaceholder")}</p>
    </section>
  );
}
