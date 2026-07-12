import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

let limiter: Ratelimit | null | undefined;

/**
 * Lazily build the Upstash limiter. When Upstash is not configured (local dev,
 * tests, CI build) rate limiting is DISABLED rather than erroring, so the app
 * runs without the credential. Wired for real once the owner supplies the
 * Upstash URL + token.
 */
function getLimiter(): Ratelimit | null {
  if (limiter !== undefined) return limiter;
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) {
    limiter = null;
    return limiter;
  }
  limiter = new Ratelimit({
    redis: new Redis({ url, token }),
    limiter: Ratelimit.slidingWindow(20, "10 s"),
    prefix: "resto:action",
  });
  return limiter;
}

/** Returns { success: false } when the key is over its budget. */
export async function checkRateLimit(key: string): Promise<{ success: boolean }> {
  const l = getLimiter();
  if (!l) return { success: true }; // disabled when unconfigured
  const { success } = await l.limit(key);
  return { success };
}
