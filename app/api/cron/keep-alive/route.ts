import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { publicEnv } from "@/lib/env";
import { isAuthorizedCron } from "@/lib/cron";

export const dynamic = "force-dynamic";

/**
 * Keep-alive cron (Vercel cron slot 1). A daily DB round-trip so the Supabase
 * free project never hits its 7-idle-day auto-pause (§3). Protected by
 * CRON_SECRET so it can't be triggered anonymously.
 */
export async function GET(request: Request) {
  if (!isAuthorizedCron(request)) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const supabase = createClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey, {
    auth: { persistSession: false },
  });
  const { error } = await supabase.rpc("health");
  if (error) {
    return NextResponse.json({ status: "error" }, { status: 503 });
  }
  return NextResponse.json({ status: "ok", pinged_at: new Date().toISOString() });
}
