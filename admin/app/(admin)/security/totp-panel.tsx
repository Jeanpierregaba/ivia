"use client";

import { AlertCircle, Copy, Printer } from "lucide-react";
import QRCode from "qrcode";
import { useActionState, useEffect, useState, useTransition } from "react";

import { ActionForm } from "@/components/action-form";
import { buttonClass, fieldClass } from "@/components/ui";
import { confirmTotp, disableTotp, regenerateCodes, startTotp, type CodesResult } from "./actions";

/** Code à 6 chiffres de l'application. */
function CodeField({ label = "Code de l'application" }: { label?: string }) {
  return (
    <label className="block text-sm">
      <span className="mb-1 block font-semibold">{label}</span>
      <input
        name="code"
        required
        inputMode="numeric"
        autoComplete="one-time-code"
        pattern="[0-9 ]{6,7}"
        maxLength={7}
        placeholder="123 456"
        className={fieldClass + " w-40 text-center font-mono text-[18px] tracking-[0.2em]"}
      />
    </label>
  );
}

function ErrorLine({ message }: { message: string }) {
  return (
    <p role="alert" className="mt-3 flex items-start gap-2 text-[14px] text-error">
      <AlertCircle size={17} aria-hidden="true" className="mt-0.5 shrink-0" />
      {message}
    </p>
  );
}

/** Codes de secours : affichés une seule fois, à copier ou imprimer. */
function RecoveryList({ codes }: { codes: string[] }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="mt-5 rounded-field border-2 border-dashed border-border-input p-5">
      <p className="font-bold">Vos 10 codes de secours</p>
      <p className="mt-1 text-[14px] text-text-secondary">
        Chacun ne sert qu&apos;une fois, si vous perdez votre téléphone. Gardez-les hors de cet ordinateur
        (papier, coffre-fort de mots de passe) : ils ne seront plus jamais affichés.
      </p>
      <ol className="mt-4 grid grid-cols-1 md:grid-cols-2 gap-2 font-mono text-[17px] font-bold">
        {codes.map((c) => (
          <li key={c} className="rounded-[10px] bg-background px-3 py-2 text-center">
            {c}
          </li>
        ))}
      </ol>
      <div className="mt-4 flex gap-2">
        <button
          type="button"
          className={buttonClass("outline")}
          onClick={async () => {
            await navigator.clipboard.writeText(codes.join("\n"));
            setCopied(true);
          }}
        >
          <Copy size={16} aria-hidden="true" /> {copied ? "Copiés" : "Copier"}
        </button>
        <button type="button" className={buttonClass("outline")} onClick={() => window.print()}>
          <Printer size={16} aria-hidden="true" /> Imprimer
        </button>
      </div>
    </div>
  );
}

/** Activation : QR code généré dans le navigateur, premier code, codes de secours. */
export function TotpEnroll() {
  const [setup, setSetup] = useState<{ secret: string; uri: string } | null>(null);
  const [qr, setQr] = useState<string>("");
  const [error, setError] = useState<string>("");
  const [starting, start] = useTransition();
  const [result, confirm, confirming] = useActionState<CodesResult, FormData>(confirmTotp, null);

  useEffect(() => {
    if (!setup) return;
    // Généré ici, jamais par un service tiers : le lien contient le secret.
    QRCode.toString(setup.uri, { type: "svg", margin: 1, width: 200, errorCorrectionLevel: "M" })
      .then(setQr)
      .catch(() => setQr(""));
  }, [setup]);

  if (result?.ok) {
    return (
      <>
        <p className="mt-5 rounded-field bg-success/10 px-4 py-3 text-[15px] font-semibold text-success">
          Application activée. Elle sera demandée à votre prochaine connexion.
        </p>
        <RecoveryList codes={result.codes} />
      </>
    );
  }

  if (!setup) {
    return (
      <div className="mt-6">
        <button
          type="button"
          disabled={starting}
          className={buttonClass("imperial")}
          onClick={() =>
            start(async () => {
              const r = await startTotp();
              if (r.ok) setSetup({ secret: r.secret, uri: r.uri });
              else setError(r.message);
            })
          }
        >
          {starting ? "Patientez…" : "Activer l'application d'authentification"}
        </button>
        {error && <ErrorLine message={error} />}
      </div>
    );
  }

  return (
    <div className="mt-6 grid gap-5">
      <ol className="list-decimal space-y-1 pl-5 text-[15px] text-text-secondary">
        <li>Ouvrez votre application d&apos;authentification et ajoutez un compte.</li>
        <li>Scannez ce QR code (ou saisissez la clé à la main).</li>
        <li>Saisissez le code à 6 chiffres affiché pour ivia.</li>
      </ol>
      <div className="flex flex-wrap items-center gap-6">
        <div
          className="size-[200px] rounded-field bg-white p-2"
          role="img"
          aria-label="QR code à scanner avec l'application d'authentification"
          // SVG produit localement par la bibliothèque qrcode à partir du lien otpauth.
          dangerouslySetInnerHTML={{ __html: qr }}
        />
        <div className="min-w-0">
          <p className="text-[13px] font-semibold text-text-muted">Clé à saisir à la main</p>
          <p className="mt-1 break-all font-mono text-[15px] font-bold tracking-wider">
            {setup.secret.match(/.{1,4}/g)?.join(" ")}
          </p>
        </div>
      </div>
      <form action={confirm} className="flex flex-wrap items-end gap-3">
        <CodeField />
        <button type="submit" disabled={confirming} className={buttonClass("imperial")}>
          {confirming ? "Vérification…" : "Activer"}
        </button>
      </form>
      {result && !result.ok && <ErrorLine message={result.message} />}
    </div>
  );
}

/** Nouveaux codes de secours, avec un code de l'application. */
export function TotpRegenerate() {
  const [result, action, pending] = useActionState<CodesResult, FormData>(regenerateCodes, null);
  if (result?.ok) return <RecoveryList codes={result.codes} />;
  return (
    <div>
      <p className="font-semibold">Nouveaux codes de secours</p>
      <p className="mb-3 text-[14px] text-text-secondary">Les anciens codes ne serviront plus.</p>
      <form action={action} className="flex flex-wrap items-end gap-3">
        <CodeField />
        <button type="submit" disabled={pending} className={buttonClass("outline")}>
          {pending ? "Patientez…" : "Générer"}
        </button>
      </form>
      {result && !result.ok && <ErrorLine message={result.message} />}
    </div>
  );
}

/** Désactivation, avec un code de l'application. */
export function TotpDisable() {
  const [code, setCode] = useState("");
  return (
    <div>
      <p className="font-semibold">Désactiver l&apos;application</p>
      <p className="mb-3 text-[14px] text-text-secondary">
        Le code par e-mail redeviendra la double vérification. Saisissez d&apos;abord un code de
        l&apos;application.
      </p>
      <label className="mb-3 block text-sm">
        <span className="mb-1 block font-semibold">Code de l&apos;application</span>
        <input
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
          inputMode="numeric"
          placeholder="123456"
          className={fieldClass + " w-40 text-center font-mono text-[18px] tracking-[0.2em]"}
        />
      </label>
      <ActionForm
        action={disableTotp}
        label="Désactiver"
        variant="outline"
        hidden={{ code }}
        confirm={{
          title: "Désactiver l'application d'authentification ?",
          body: "Votre accès ne sera plus protégé que par le mot de passe et un code envoyé par e-mail.",
        }}
      />
    </div>
  );
}
