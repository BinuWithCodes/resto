/**
 * Public env — inlined at build time, safe in the client bundle.
 * Only NEXT_PUBLIC_* values belong here.
 */
export const publicEnv = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "",
};

/**
 * Server-only secret accessor. Throws at CALL time (never at import/build time)
 * if the variable is missing, so a missing secret fails loudly at the point of
 * use rather than silently. Never call this from client components (§4.2).
 */
export function serverEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required server env var: ${name}`);
  }
  return value;
}
