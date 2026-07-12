/**
 * Error-reporting seam. Real Sentry capture (with beforeSend filter + daily
 * cap, tracing OFF) is wired in Phase 0 step 0.11. Until then this logs in dev
 * only and never leaks details to the client (§4.5).
 */
export function captureException(error: unknown, context?: Record<string, unknown>): void {
  if (process.env.NODE_ENV !== "production") {
    console.error("[captureException]", error, context ?? {});
  }
}
