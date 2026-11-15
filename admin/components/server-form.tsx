"use client";

import { AlertCircle, CheckCircle2 } from "lucide-react";
import { useActionState } from "react";

import type { ActionResult } from "@/lib/api";
import { buttonClass, cx, type ButtonVariant } from "./ui";

type Props = {
  action: (prev: ActionResult | null, form: FormData) => Promise<ActionResult>;
  submitLabel: string;
  variant?: ButtonVariant;
  children: React.ReactNode;
  className?: string;
  // Disposition en ligne (édition d'une ligne de tableau) plutôt qu'en colonne.
  inline?: boolean;
};

/**
 * Formulaire branché sur une Server Action (protégée contre le CSRF par Next.js) : champs libres,
 * bouton d'envoi, puis message de l'API (succès ou erreur, champ par champ si l'API les précise).
 */
export function ServerForm({ action, submitLabel, variant = "primary", children, className, inline }: Props) {
  const [state, formAction, pending] = useActionState(action, null);
  const fieldErrors = state && !state.ok && state.fields ? Object.values(state.fields) : [];
  return (
    <form action={formAction} className={className}>
      <div className={inline ? "flex flex-wrap items-end gap-2" : "space-y-4"}>
        {children}
        <button type="submit" disabled={pending} className={buttonClass(variant, inline ? "" : "mt-1")}>
          {pending ? "Patientez…" : submitLabel}
        </button>
      </div>
      {state && (
        <p
          role="status"
          className={cx(
            "mt-2 flex items-start gap-1.5 text-[13px]",
            state.ok ? "text-success" : "text-error",
          )}
        >
          {state.ok ? (
            <CheckCircle2 size={15} aria-hidden="true" className="mt-px shrink-0" />
          ) : (
            <AlertCircle size={15} aria-hidden="true" className="mt-px shrink-0" />
          )}
          {state.message}
          {fieldErrors.length > 0 && ` (${fieldErrors.join(" ")})`}
        </p>
      )}
    </form>
  );
}
