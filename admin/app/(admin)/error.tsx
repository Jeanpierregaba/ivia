"use client";

import { buttonClass } from "@/components/ui";

// Erreur inattendue dans une page admin : message sans détail technique et action « Réessayer ».
export default function AdminError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div role="alert" className="rounded-card bg-surface p-6">
      <h1 className="text-[22px] font-bold">Une erreur inattendue est survenue</h1>
      <p className="mt-2 text-text-secondary">
        Réessayez dans un instant. Si le problème continue, prévenez l&apos;équipe technique.
      </p>
      <button onClick={reset} className={buttonClass("primary", "mt-4")}>
        Réessayer
      </button>
    </div>
  );
}
