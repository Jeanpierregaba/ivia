// Squelette affiché pendant le chargement d'une page admin (DESIGN.md « États à toujours prévoir »).
export default function Loading() {
  return (
    <div aria-busy="true" aria-label="Chargement" className="animate-pulse space-y-4">
      <div className="h-8 w-64 rounded-full bg-border" />
      <div className="h-40 rounded-card bg-surface" />
      <div className="h-64 rounded-card bg-surface" />
    </div>
  );
}
