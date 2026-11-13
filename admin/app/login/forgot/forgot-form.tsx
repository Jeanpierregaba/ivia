"use client";

import { AlertCircle, ArrowLeft, Mail } from "lucide-react";
import Link from "next/link";
import { useActionState } from "react";

import { buttonClass } from "@/components/ui";
import { forgotPassword, resetPassword, type FormState } from "../actions";
import { authFieldClass } from "../auth-shell";

/**
 * Mot de passe oublié : adresse (code envoyé si le compte existe), puis code et nouveau mot de
 * passe ; la double vérification suit (B02).
 */
export function ForgotForm() {
  const [sent, send, sending] = useActionState<FormState, FormData>(forgotPassword, {});
  const [reset, submit, resetting] = useActionState<FormState, FormData>(resetPassword, {});
  const email = reset.info ?? sent.info;

  return (
    <div className="animate-rise">
      <Link
        href="/login"
        className="mb-6 inline-flex items-center gap-1.5 text-[14px] font-bold text-text-secondary hover:text-text"
      >
        <ArrowLeft size={17} aria-hidden="true" /> Retour à la connexion
      </Link>
      <p className="text-[13px] font-bold uppercase tracking-[0.12em] text-primary">Espace administrateur</p>
      <h1 className="mt-3 text-[40px] font-extrabold leading-[34px] tracking-[-0.03em]">
        Mot de passe oublié
      </h1>

      {!email ? (
        <form action={send} className="mt-8 space-y-5">
          <p className="text-[14px] text-text-secondary">
            Indiquez votre e-mail professionnel : vous recevrez un code pour choisir un nouveau mot de passe.
          </p>
          <label className="block">
            <span className="mb-2 block text-[14px] font-bold">E-mail</span>
            <input
              name="email"
              type="email"
              required
              autoComplete="username"
              autoFocus
              className={authFieldClass}
            />
            {sent.fields?.recipient && (
              <span className="mt-1.5 block text-[13px] text-error">{sent.fields.recipient}</span>
            )}
          </label>
          {sent.error && <ErrorLine message={sent.error} />}
          <button
            type="submit"
            disabled={sending}
            className={buttonClass("imperial", "!h-[56px] w-full !rounded-[14px] text-[15px]")}
          >
            {sending ? "Envoi…" : "Recevoir le code"}
          </button>
        </form>
      ) : (
        <form action={submit} className="mt-8 space-y-5">
          <p className="flex items-start gap-3 rounded-[14px] bg-secondary-soft px-4 py-3 text-[14px] text-tertiary">
            <Mail size={18} aria-hidden="true" className="mt-0.5 shrink-0" />
            <span>
              Si un compte existe pour <strong>{email}</strong>, un code à 6 chiffres vient d&apos;y être
              envoyé (valable 10 min).
            </span>
          </p>
          <input type="hidden" name="email" value={email} />
          <label className="block">
            <span className="mb-2 block text-[14px] font-bold">Code reçu</span>
            <input
              name="code"
              inputMode="numeric"
              pattern="[0-9]{6}"
              maxLength={6}
              required
              autoFocus
              autoComplete="one-time-code"
              className={authFieldClass + " text-center text-[24px] font-extrabold tracking-[0.5em]"}
            />
          </label>
          <label className="block">
            <span className="mb-2 block text-[14px] font-bold">Nouveau mot de passe</span>
            <input
              name="password"
              type="password"
              required
              minLength={10}
              maxLength={128}
              autoComplete="new-password"
              className={authFieldClass}
            />
            <span className="mt-1.5 block text-[13px] text-text-muted">
              10 caractères au moins. Une phrase facile à retenir fait un bon mot de passe.
            </span>
            {reset.fields?.password && (
              <span className="mt-1 block text-[13px] text-error">{reset.fields.password}</span>
            )}
          </label>
          {reset.error && !reset.fields?.password && <ErrorLine message={reset.error} />}
          <button
            type="submit"
            disabled={resetting}
            className={buttonClass("imperial", "!h-[56px] w-full !rounded-[14px] text-[15px]")}
          >
            {resetting ? "Enregistrement…" : "Changer le mot de passe"}
          </button>
        </form>
      )}
    </div>
  );
}

function ErrorLine({ message }: { message: string }) {
  return (
    <p role="alert" className="animate-rise flex items-start gap-2 text-[14px] text-error">
      <AlertCircle size={17} aria-hidden="true" className="mt-0.5 shrink-0" />
      {message}
    </p>
  );
}
