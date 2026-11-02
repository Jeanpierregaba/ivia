"use client";

import { AlertCircle, ArrowRight, Mail } from "lucide-react";
import { useActionState } from "react";

import { buttonClass } from "@/components/ui";
import { login, type LoginState } from "./actions";

// Champs comme dans les apps (DESIGN.md) : libellé au-dessus, contour 3:1 au repos, Imperial 2 px
// quand le champ est actif.
const fieldClass =
  "h-14 w-full rounded-field border border-border-input bg-surface px-4 text-[15px] outline-none transition-colors focus:border-2 focus:border-primary focus:px-[15px]";
const initial: LoginState = { step: "email", email: "" };

export function LoginForm() {
  const [state, action, pending] = useActionState(login, initial);

  return (
    <form action={action} className="space-y-5">
      {state.step === "email" ? (
        <>
          <input type="hidden" name="step" value="email" />
          <label className="block">
            <span className="mb-2 block text-[13px] font-semibold text-text-secondary">Adresse e-mail</span>
            <input
              name="email"
              type="email"
              required
              autoComplete="email"
              autoFocus
              placeholder="prenom@ivia.tg"
              defaultValue={state.email}
              className={fieldClass}
            />
          </label>
        </>
      ) : (
        <>
          <input type="hidden" name="step" value="code" />
          <div className="flex items-start gap-3 rounded-field bg-secondary-soft px-4 py-3 text-tertiary">
            <Mail size={18} aria-hidden="true" className="mt-0.5 shrink-0" />
            <p className="text-[13px] leading-[18px]">
              Code envoyé à <strong>{state.email}</strong>. Vérifiez aussi vos courriers indésirables.
            </p>
          </div>
          <label className="block">
            <span className="mb-2 block text-[13px] font-semibold text-text-secondary">
              Code à 6 chiffres
            </span>
            <input
              name="code"
              inputMode="numeric"
              pattern="[0-9]{6}"
              maxLength={6}
              required
              autoFocus
              autoComplete="one-time-code"
              placeholder="••••••"
              className={fieldClass + " text-center text-[28px] font-semibold tracking-[0.5em]"}
            />
          </label>
        </>
      )}

      {state.error && (
        <p role="alert" className="flex items-start gap-2 text-[13px] text-error">
          <AlertCircle size={16} aria-hidden="true" className="mt-px shrink-0" />
          {state.error}
        </p>
      )}

      <button type="submit" disabled={pending} className={buttonClass("imperial", "h-[54px] w-full")}>
        {pending ? "Patientez…" : state.step === "email" ? "Recevoir un code" : "Se connecter"}
        {!pending && <ArrowRight size={18} aria-hidden="true" />}
      </button>
      {state.step === "code" && (
        <button
          type="submit"
          name="step"
          value="restart"
          formNoValidate
          className={buttonClass("ghost", "w-full")}
        >
          Changer d&apos;adresse
        </button>
      )}
    </form>
  );
}
