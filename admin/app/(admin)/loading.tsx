// Squelette affiché pendant le chargement d'une page admin (DESIGN.md « États à toujours prévoir »).
export default function Loading() {
  return (
    <div aria-busy="true" aria-label="Chargement" className="animate-pulse">
      <div className="mb-2 h-3 w-28 rounded-full bg-border" />
      <div className="mb-8 h-9 w-96 rounded-full bg-border" />
      <div className="mb-4 grid grid-cols-4 gap-2">
        <div className="h-36 rounded-tile rounded-tl-[18px] bg-surface" />
        <div className="h-36 rounded-tile bg-surface" />
        <div className="h-36 rounded-tile bg-surface" />
        <div className="h-36 rounded-tile rounded-tr-[18px] bg-surface" />
      </div>
      <div className="h-64 rounded-field bg-surface" />
    </div>
  );
}
