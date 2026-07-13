import Link from "next/link";
import { getTranslations } from "next-intl/server";

export default async function StaffPage() {
  const t = await getTranslations();
  return (
    <section className="p-4 sm:p-6">
      <h1 className="text-xl font-semibold">{t("nav.staff")}</h1>
      <nav className="mt-4 flex flex-col gap-2 text-sm">
        <Link href="/staff/payroll" className="text-blue-600 hover:underline">
          {t("staff.payroll")}
        </Link>
      </nav>
    </section>
  );
}
