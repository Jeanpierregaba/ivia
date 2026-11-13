"use client";

import { useActionState, useRef } from "react";

import type { ActionResult } from "@/lib/api";
import { buttonClass, type ButtonVariant } from "./ui";

type Props = {
  action: (prev: ActionResult | null, form: FormData) => Promise<ActionResult>;
  label: string;
  variant?: ButtonVariant;
  // Confirmation : rappelle l'objet (et le montant) avant une action sensible (DESIGN.md).
  confirm?: { title: string; body: string };
  // Motif demandé à l'admin (obligatoire quand required).
  reason?: { label: string; required?: boolean };
  hidden?: Record<string, string>;
};

/**
 * Bouton d'action admin : formulaire vers une Server Action (protégée contre le CSRF par Next.js),
 * avec boîte de confirmation native et motif facultatif. Le résultat (message de l'API) s'affiche
 * sous le bouton.
 */
export function ActionForm({ action, label, variant = "primary", confirm, reason, hidden }: Props) {
  const [state, formAction, pending] = useActionState(action, null);
  const dialog = useRef<HTMLDialogElement>(null);

  const fields = (
    <>
      {Object.entries(hidden ?? {}).map(([k, v]) => (
        <input key={k} type="hidden" name={k} value={v} />
      ))}
      {reason && (
        <label className="mt-3 block text-sm">
          <span className="mb-1 block font-semibold">{reason.label}</span>
          <textarea
            name="reason"
            required={reason.required}
            maxLength={500}
            rows={3}
            className="w-full rounded-field border border-border-input bg-surface px-3 py-2"
          />
        </label>
      )}
    </>
  );

  const result = state && (
    <p role="status" className={state.ok ? "mt-2 text-sm text-success" : "mt-2 text-sm text-error"}>
      {state.ok ? "✓ " : "✕ "}
      {state.message}
    </p>
  );

  if (!confirm && !reason) {
    return (
      <form action={formAction}>
        {fields}
        <button type="submit" disabled={pending} className={buttonClass(variant)}>
          {pending ? "Patientez…" : label}
        </button>
        {result}
      </form>
    );
  }

  return (
    <div>
      <button type="button" className={buttonClass(variant)} onClick={() => dialog.current?.showModal()}>
        {label}
      </button>
      {result}
      <dialog
        ref={dialog}
        className="soft-dialog m-auto w-[min(480px,calc(100vw-2rem))] rounded-card p-6 backdrop:bg-tertiary/40 backdrop:backdrop-blur-[2px]"
      >
        <form action={formAction} onSubmit={() => dialog.current?.close()}>
          <h2 className="text-[22px] font-bold leading-7">{confirm?.title ?? label}</h2>
          {confirm && <p className="mt-2 text-text-secondary">{confirm.body}</p>}
          {fields}
          <div className="mt-6 flex justify-end gap-2">
            <button type="button" className={buttonClass("outline")} onClick={() => dialog.current?.close()}>
              Annuler
            </button>
            <button type="submit" disabled={pending} className={buttonClass(variant)}>
              {label}
            </button>
          </div>
        </form>
      </dialog>
    </div>
  );
}
