"use client";

import { AlertCircle, ArrowLeft, Check } from "lucide-react";
import { useActionState, useEffect, useRef, useState, useTransition } from "react";

import { buttonClass, cx } from "@/components/ui";
import { resendCode, restart, verifyCode, type FormState } from "../actions";

const LENGTH = 6;
const RESEND_AFTER = 60; // secondes, comme l'API (1 code par minute)

/**
 * Code en 6 cases : saisie, collage du code entier, retour arrière (B02). Par e-mail : renvoi minuté.
 * Application d'authentification : pas de renvoi, mais un code de secours possible.
 */
export function CodeForm({ email, method }: { email: string; method: "email" | "totp" }) {
  const totp = method === "totp";
  const [recovery, setRecovery] = useState(false);
  const [recoveryCode, setRecoveryCode] = useState("");
  const [digits, setDigits] = useState<string[]>(Array(LENGTH).fill(""));
  // Code faux : les cases se vident et la saisie reprend au début.
  const [state, action, pending] = useActionState<FormState, FormData>(async (prev, form) => {
    const result = await verifyCode(prev, form);
    if (result.error) {
      setDigits(Array(LENGTH).fill(""));
      requestAnimationFrame(() => boxes.current[0]?.focus());
    }
    return result;
  }, {});
  const [left, setLeft] = useState(RESEND_AFTER);
  const [resent, setResent] = useState<FormState>({});
  const [resending, startResend] = useTransition();
  const boxes = useRef<(HTMLInputElement | null)[]>([]);
  const code = recovery ? recoveryCode : digits.join("");
  const ready = recovery ? recoveryCode.replace(/[^A-Za-z0-9]/g, "").length === 8 : code.length === LENGTH;

  useEffect(() => {
    if (left <= 0) return;
    const t = setTimeout(() => setLeft((s) => s - 1), 1000);
    return () => clearTimeout(t);
  }, [left]);

  const fill = (from: number, value: string) => {
    const chars = value
      .replace(/\D/g, "")
      .slice(0, LENGTH - from)
      .split("");
    if (chars.length === 0) return;
    setDigits((d) => {
      const next = [...d];
      chars.forEach((c, i) => (next[from + i] = c));
      return next;
    });
    boxes.current[Math.min(from + chars.length, LENGTH - 1)]?.focus();
  };

  const onKey = (i: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Backspace" && !digits[i] && i > 0) {
      setDigits((d) => d.map((v, j) => (j === i - 1 ? "" : v)));
      boxes.current[i - 1]?.focus();
      e.preventDefault();
    } else if (e.key === "ArrowLeft" && i > 0) boxes.current[i - 1]?.focus();
    else if (e.key === "ArrowRight" && i < LENGTH - 1) boxes.current[i + 1]?.focus();
  };

  const resend = () =>
    startResend(async () => {
      const r = await resendCode();
      setResent(r);
      if (!r.error) setLeft(RESEND_AFTER);
    });

  return (
    <div className="animate-rise">
      <form action={restart}>
        <button
          type="submit"
          className="mb-6 inline-flex items-center gap-1.5 text-[14px] font-bold text-text-secondary hover:text-text"
        >
          <ArrowLeft size={17} aria-hidden="true" /> Changer d&apos;e-mail
        </button>
      </form>
      <h1 className="text-[40px] font-extrabold leading-[34px] tracking-[-0.03em]">
        {recovery ? "Code de secours" : "Code de vérification"}
      </h1>
      <p className="mt-3 text-[14px] text-text-secondary">
        {recovery ? (
          <>
            Saisissez l&apos;un de vos 10 codes de secours (format XXXX-XXXX). Chacun ne sert qu&apos;une
            fois.
          </>
        ) : totp ? (
          <>
            Ouvrez votre application d&apos;authentification et saisissez le code à 6 chiffres affiché pour{" "}
            <strong className="text-text">ivia</strong> ({email}).
          </>
        ) : (
          <>
            Code envoyé à <strong className="text-text">{email}</strong>.
          </>
        )}
      </p>

      <form action={action} className="mt-8">
        <input type="hidden" name="code" value={code} />
        {recovery ? (
          <label className="block">
            <span className="sr-only">Code de secours</span>
            <input
              value={recoveryCode}
              onChange={(e) => setRecoveryCode(e.target.value.toUpperCase().slice(0, 9))}
              autoFocus
              autoComplete="off"
              spellCheck={false}
              placeholder="XXXX-XXXX"
              className="h-[64px] w-full rounded-[14px] bg-background px-5 text-center font-mono text-[24px] font-extrabold tracking-[0.2em] outline-none focus:bg-surface focus:shadow-[inset_0_0_0_2px_var(--color-primary)]"
            />
          </label>
        ) : (
          <fieldset>
            <legend className="sr-only">Code à 6 chiffres</legend>
            <div
              className="grid grid-cols-6 gap-3"
              onPaste={(e) => (e.preventDefault(), fill(0, e.clipboardData.getData("text")))}
            >
              {digits.map((d, i) => (
                <input
                  key={i}
                  ref={(el) => {
                    boxes.current[i] = el;
                  }}
                  value={d}
                  onChange={(e) =>
                    e.target.value
                      ? fill(i, e.target.value)
                      : setDigits((x) => x.map((v, j) => (j === i ? "" : v)))
                  }
                  onKeyDown={(e) => onKey(i, e)}
                  onFocus={(e) => e.target.select()}
                  inputMode="numeric"
                  autoComplete={i === 0 ? "one-time-code" : "off"}
                  autoFocus={i === 0}
                  maxLength={LENGTH}
                  aria-label={`Chiffre ${i + 1} sur ${LENGTH}`}
                  className={cx(
                    "h-[64px] w-full rounded-[14px] bg-background text-center text-[30px] font-extrabold caret-primary outline-none transition-all",
                    "focus:bg-surface focus:shadow-[inset_0_0_0_2px_var(--color-primary)]",
                    d && "bg-background text-text",
                  )}
                />
              ))}
            </div>
          </fieldset>
        )}

        {totp ? (
          <div className="mt-4 flex justify-between text-[14px] text-text-secondary">
            <button
              type="button"
              onClick={() => setRecovery((r) => !r)}
              className="font-bold text-secondary hover:underline"
            >
              {recovery ? "Utiliser l'application" : "Téléphone perdu ? Utiliser un code de secours"}
            </button>
            {!recovery && <span>Nouveau code toutes les 30 s</span>}
          </div>
        ) : (
          <div className="mt-4 flex justify-between text-[14px] text-text-secondary">
            {left > 0 ? (
              <span aria-live="polite">
                Renvoyer le code dans{" "}
                <strong className="tabular-nums text-text">0:{String(left).padStart(2, "0")}</strong>
              </span>
            ) : (
              <button
                type="button"
                onClick={resend}
                disabled={resending}
                className="font-bold text-secondary hover:underline"
              >
                {resending ? "Envoi…" : "Renvoyer le code"}
              </button>
            )}
            <span>Valable 10 min</span>
          </div>
        )}
        {resent.info && <p className="mt-2 text-[13px] text-success">{resent.info}</p>}

        <label className="mt-7 flex cursor-pointer items-center gap-3 text-[14px]">
          <input type="checkbox" name="remember" defaultChecked className="peer sr-only" />
          <span className="grid size-[24px] place-items-center rounded-[7px] border-2 border-border-input bg-surface text-white peer-checked:border-tertiary peer-checked:bg-tertiary peer-focus-visible:outline-2 peer-focus-visible:outline-secondary">
            <Check size={16} strokeWidth={3} aria-hidden="true" />
          </span>
          Rester connecté 8 heures sur cet ordinateur
        </label>

        {(state.error || resent.error) && (
          <p role="alert" className="animate-rise mt-5 flex items-start gap-2 text-[14px] text-error">
            <AlertCircle size={17} aria-hidden="true" className="mt-0.5 shrink-0" />
            {state.error ?? resent.error}
          </p>
        )}

        <button
          type="submit"
          disabled={pending || !ready}
          className={buttonClass("imperial", "mt-7 !h-[56px] w-full !rounded-[14px] text-[15px]")}
        >
          {pending ? "Vérification…" : "Se connecter"}
        </button>
      </form>
    </div>
  );
}
