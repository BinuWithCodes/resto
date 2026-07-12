"use server";

import { cookies } from "next/headers";
import { defaultLocale, LOCALE_COOKIE, locales } from "@/i18n/request";

/** Server Action: persist the chosen locale in a cookie (validated server-side). */
export async function setLocaleAction(locale: string): Promise<void> {
  const value = (locales as readonly string[]).includes(locale) ? locale : defaultLocale;
  const store = await cookies();
  store.set(LOCALE_COOKIE, value, {
    path: "/",
    maxAge: 60 * 60 * 24 * 365,
    sameSite: "lax",
  });
}
