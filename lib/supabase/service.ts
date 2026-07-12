import { createClient } from "@supabase/supabase-js";
import { publicEnv, serverEnv } from "@/lib/env";

/**
 * service_role Supabase client — **BYPASSES RLS**. Server-only.
 *
 * Every call site MUST justify in a comment why it needs to bypass RLS (§4.2),
 * e.g. cron jobs writing system_metrics, or the auth hook. Never import this
 * into a client component; the runtime guard below is a last line of defence.
 */
export function getServiceSupabase() {
  if (typeof window !== "undefined") {
    throw new Error("service_role client must never run in the browser");
  }
  return createClient(publicEnv.supabaseUrl, serverEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
