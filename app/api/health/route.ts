import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { publicEnv } from "@/lib/env";

export const dynamic = "force-dynamic";

/**
 * Liveness + DB reachability probe for UptimeRobot. Calls the cheap `health()`
 * function (a `select 1`) via the anon key — no cookies, no session, no table
 * read. Returns 503 if the DB is unreachable so uptime monitoring can alert.
 */
export async function GET() {
  try {
    const supabase = createClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey, {
      auth: { persistSession: false },
    });
    const { error } = await supabase.rpc("health");
    if (error) {
      return NextResponse.json({ status: "error", db: "down" }, { status: 503 });
    }
    return NextResponse.json({ status: "ok", db: "ok" });
  } catch {
    return NextResponse.json({ status: "error", db: "down" }, { status: 503 });
  }
}
