import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { publicEnv } from "@/lib/env";

/**
 * Server Supabase client (anon key, RLS-gated) bound to the request cookies.
 * Connects via the Supavisor transaction pooler in production (§4.3).
 * Use inside Server Components, Route Handlers, and Server Actions.
 */
export async function getServerSupabase() {
  const cookieStore = await cookies();
  return createServerClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (cookiesToSet) => {
        try {
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
        } catch {
          // Called from a Server Component render (read-only cookies) — safe to
          // ignore; the session is refreshed in middleware.
        }
      },
    },
  });
}
