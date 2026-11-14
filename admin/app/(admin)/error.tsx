"use client";

import { AlertTriangle, RotateCcw } from "lucide-react";

import { buttonClass } from "@/components/ui";

// Erreur inattendue dans une page admin : message sans détail technique et action « Réessayer ».
export default function AdminError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div role="alert" className="flex flex-col items-center rounded-field bg-surface px-6 py-14 text-center">
      <span className="mb-4 grid size-14 place-items-center rounded-full bg-primary-soft text-error">
        <AlertTriangle size={26} aria-hidden="true" />
      </span>
      <h1 className="text-[18px] font-bold">Une erreur inattendue est survenue</h1>
      <p className="mt-2 max-w-md text-text-secondary">
        Réessayez dans un instant. Si le problème continue, prévenez l&apos;équipe technique.
      </p>
      <button onClick={reset} className={buttonClass("primary", "mt-6")}>
        <RotateCcw size={16} aria-hidden="true" /> Réessayer
      </button>
    </div>
  );
}
