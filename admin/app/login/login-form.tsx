"use client";

import { useActionState } from "react";

import { buttonClass } from "@/components/ui";
import { login, type LoginState } from "./actions";

const fieldClass = "w-full rounded-field border border-border-input bg-surface px-4 py-3";
const initial: LoginState = { step: "email", email: "" };

export function LoginForm() {
  const [state, action, pending] = useActionState(login, initial);

  return (
    <form action={action} className="space-y-4">
      {state.step === "email" ? (
        <>
          <input type="hidden" name="step" value="email" />
          <label className="block">
            <span className="mb-1 block font-semibold">Adresse e-mail</span>
            <input
              name="email"
              type="email"
              required
              autoComplete="email"
              defaultValue={state.email}
              className={fieldClass}
            />
          </label>
        </>
      ) : (
        <>
          <input type="hidden" name="step" value="code" />
          <p className="text-text-secondary">
            Code envoyé à <strong className="text-text">{state.email}</strong>.
          </p>
          <label className="block">
            <span className="mb-1 block font-semibold">Code de connexion</span>
            <input
              name="code"
              inputMode="numeric"
              pattern="[0-9]{6}"
              maxLength={6}
              required
              autoComplete="one-time-code"
              className={fieldClass + " tracking-[0.4em]"}
            />
          </label>
        </>
      )}

      {state.error ? (
        <p role="alert" className="text-sm text-error">
          <span aria-hidden="true">✕ </span>
          {state.error}
        </p>
      ) : (
        state.info && (
          <p role="status" className="text-sm text-text-secondary">
            {state.info}
          </p>
        )
      )}

      <button type="submit" disabled={pending} className={buttonClass("primary", "w-full")}>
        {pending ? "Patientez…" : state.step === "email" ? "Recevoir un code" : "Se connecter"}
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
