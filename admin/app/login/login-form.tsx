"use client";

import { AlertCircle, Eye, EyeOff } from "lucide-react";
import { useActionState, useState } from "react";

import { buttonClass } from "@/components/ui";
import { passwordLogin, type FormState } from "./actions";
import { authFieldClass } from "./auth-shell";

export function LoginForm() {
  const [state, action, pending] = useActionState<FormState, FormData>(passwordLogin, {});
  const [visible, setVisible] = useState(false);

  return (
    <form action={action} className="space-y-5">
      <label className="block">
        <span className="mb-2 block text-[15px] font-bold">E-mail</span>
        <input
          name="email"
          type="email"
          required
          autoComplete="username"
          autoFocus
          placeholder="prenom.nom@ivia.tg"
          className={authFieldClass}
        />
        {state.fields?.email && (
          <span className="mt-1.5 block text-[13px] text-error">{state.fields.email}</span>
        )}
      </label>
      <label className="block">
        <span className="mb-2 block text-[15px] font-bold">Mot de passe</span>
        <span className="relative block">
          <input
            name="password"
            type={visible ? "text" : "password"}
            required
            autoComplete="current-password"
            className={authFieldClass + " pr-12"}
          />
          <button
            type="button"
            onClick={() => setVisible((v) => !v)}
            aria-label={visible ? "Masquer le mot de passe" : "Afficher le mot de passe"}
            className="absolute right-2 top-1/2 grid size-9 -translate-y-1/2 place-items-center rounded-full text-text-muted hover:bg-background"
          >
            {visible ? <EyeOff size={18} aria-hidden="true" /> : <Eye size={18} aria-hidden="true" />}
          </button>
        </span>
      </label>

      {state.error && (
        <p role="alert" className="animate-rise flex items-start gap-2 text-[14px] text-error">
          <AlertCircle size={17} aria-hidden="true" className="mt-0.5 shrink-0" />
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={pending}
        className={buttonClass("imperial", "!h-[56px] w-full !rounded-[14px] text-[17px]")}
      >
        {pending ? "Vérification…" : "Recevoir le code"}
      </button>
    </form>
  );
}
