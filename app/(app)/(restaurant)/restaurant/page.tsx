import Link from "next/link";
import { getTranslations } from "next-intl/server";

export default async function RestaurantPage() {
  const t = await getTranslations();
  return (
    <section className="p-4 sm:p-6">
      <h1 className="text-xl font-semibold">{t("nav.restaurant")}</h1>
      <nav className="mt-4 flex flex-col gap-2 text-sm">
        <Link href="/restaurant/purchases" className="text-blue-600 hover:underline">
          {t("restaurant.purchases")}
        </Link>
      </nav>
    </section>
  );
}
