"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import { cn } from "@/lib/utils";

const ITEMS = [
  { key: "dashboard", href: "/" },
  { key: "restaurant", href: "/restaurant" },
  { key: "hostel", href: "/hostel" },
  { key: "staff", href: "/staff" },
  { key: "settings", href: "/settings" },
] as const;

function useItems(showSettings: boolean) {
  return ITEMS.filter((item) => item.key !== "settings" || showSettings);
}

function isActive(pathname: string, href: string) {
  return href === "/" ? pathname === "/" : pathname.startsWith(href);
}

/**
 * Area navigation. `variant="bottom"` is the thumb-reachable mobile bar;
 * `variant="sidebar"` is the md+ left rail (design-system/MASTER.md §5).
 * Settings is omitted entirely for non-super_admin (gating passed from server).
 */
export function MainNav({
  variant,
  showSettings = true,
}: {
  variant: "bottom" | "sidebar";
  showSettings?: boolean;
}) {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const items = useItems(showSettings);

  if (variant === "bottom") {
    return (
      <nav
        aria-label="Primary"
        className="bg-background fixed inset-x-0 bottom-0 z-40 flex border-t md:hidden"
      >
        {items.map((item) => {
          const active = isActive(pathname, item.href);
          return (
            <Link
              key={item.key}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex min-h-14 flex-1 items-center justify-center px-1 text-center text-xs font-medium",
                active ? "text-foreground" : "text-muted-foreground",
              )}
            >
              {t(item.key)}
            </Link>
          );
        })}
      </nav>
    );
  }

  return (
    <nav aria-label="Primary" className="hidden md:flex md:flex-col md:gap-1">
      {items.map((item) => {
        const active = isActive(pathname, item.href);
        return (
          <Link
            key={item.key}
            href={item.href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "rounded-md px-3 py-2 text-sm font-medium",
              active
                ? "bg-secondary text-foreground"
                : "text-muted-foreground hover:bg-secondary/60",
            )}
          >
            {t(item.key)}
          </Link>
        );
      })}
    </nav>
  );
}
