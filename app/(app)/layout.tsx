import { getTranslations } from "next-intl/server";
import { MainNav } from "@/components/main-nav";
import { LanguageSwitcher } from "@/components/language-switcher";

/**
 * Shell for the authenticated areas (dashboard/restaurant/hostel/staff/settings).
 * The login route lives outside this group and gets no shell.
 */
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const t = await getTranslations("app");

  // TODO(0.7): read the caller's role server-side and hide Settings for
  // non-super_admin (design-system/MASTER.md §5). Defaults to visible until auth.
  const showSettings = true;

  return (
    <div className="flex min-h-full flex-col">
      <header className="bg-background sticky top-0 z-30 flex h-14 items-center justify-between border-b px-4">
        <div className="flex items-baseline gap-2">
          <span className="font-semibold">{t("name")}</span>
          <span className="text-muted-foreground hidden text-xs sm:inline">{t("tagline")}</span>
        </div>
        <LanguageSwitcher />
      </header>

      <div className="flex flex-1">
        <aside className="hidden w-48 shrink-0 border-r p-3 md:block">
          <MainNav variant="sidebar" showSettings={showSettings} />
        </aside>
        <main className="min-w-0 flex-1 pb-16 md:pb-0">{children}</main>
      </div>

      <MainNav variant="bottom" showSettings={showSettings} />
    </div>
  );
}
