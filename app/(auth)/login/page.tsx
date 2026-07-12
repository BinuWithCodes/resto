import { getTranslations } from "next-intl/server";

// Login lives outside the (app) shell. Real auth wired in step 0.7.
export default async function LoginPage() {
  const t = await getTranslations();
  return (
    <main className="mx-auto flex min-h-full w-full max-w-sm flex-col justify-center p-6">
      <h1 className="text-xl font-semibold">{t("auth.login")}</h1>
      <p className="text-muted-foreground mt-2 text-sm">{t("auth.loginPlaceholder")}</p>
    </main>
  );
}
