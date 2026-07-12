"use client";

import { useLocale, useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useTransition } from "react";
import { setLocaleAction } from "@/lib/i18n-actions";
import { cn } from "@/lib/utils";

const OPTIONS = [
  { locale: "en", short: "EN" },
  { locale: "ta", short: "தமிழ்" },
] as const;

/** Sets the locale via a Server Action, then refreshes to re-render in the new language. */
export function LanguageSwitcher() {
  const active = useLocale();
  const t = useTranslations("common");
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function select(locale: string) {
    startTransition(async () => {
      await setLocaleAction(locale);
      router.refresh();
    });
  }

  return (
    <div role="group" aria-label={t("language")} className="flex items-center gap-1">
      {OPTIONS.map((option) => (
        <button
          key={option.locale}
          type="button"
          onClick={() => select(option.locale)}
          disabled={pending}
          aria-pressed={active === option.locale}
          className={cn(
            "min-h-9 rounded-md px-2 text-sm font-medium",
            active === option.locale
              ? "bg-secondary text-foreground"
              : "text-muted-foreground hover:bg-secondary/60",
          )}
        >
          {option.short}
        </button>
      ))}
    </div>
  );
}
