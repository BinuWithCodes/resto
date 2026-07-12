// Placeholder home (owner dashboard). Real shell + cards land in Phase 0 step 0.9 / Phase 4.
// Route group "(dashboard)" adds no URL segment, so this renders at "/".
export default function DashboardHome() {
  return (
    <main className="p-6">
      <h1 className="text-xl font-semibold">Resto — Operations Console</h1>
      <p className="text-muted-foreground mt-2 text-sm">
        Phase 0 scaffold. Dashboard cards arrive in a later step.
      </p>
    </main>
  );
}
