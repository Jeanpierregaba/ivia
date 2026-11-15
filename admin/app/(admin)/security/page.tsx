import { KeyRound, MonitorSmartphone, ShieldCheck } from "lucide-react";

import { ActionForm } from "@/components/action-form";
import { Card, CardTitle, ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime } from "@/lib/format";
import { revokeSession } from "./actions";
import { TotpDisable, TotpEnroll, TotpRegenerate } from "./totp-panel";

export const metadata = { title: "Sécurité" };

// Sécurité du compte admin (spec 001 v2, ADR 0012).
export default async function SecurityPage() {
  let info: Schemas["SessionInfo"];
  let sessions: Schemas["SessionList"];
  try {
    [info, sessions] = await Promise.all([
      api<Schemas["SessionInfo"]>("/v1/auth/session"),
      api<Schemas["SessionList"]>("/v1/me/sessions"),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const totp = info.mfa_method === "totp";

  return (
    <>
      <PageHeader
        overline="Mon compte"
        title="Sécurité de votre accès"
        highlight="Sécurité"
        description="Le back-office manipule l'argent et les comptes : protégez votre accès avec une application d'authentification, et surveillez vos sessions ouvertes."
      />
      <div className="grid gap-6 xl:grid-cols-2">
        <Card>
          <CardTitle icon={<ShieldCheck size={18} aria-hidden="true" />}>Double vérification</CardTitle>
          {totp ? (
            <>
              <p className="rounded-field bg-success/10 px-4 py-3 text-[14px] font-semibold text-success">
                Application d&apos;authentification activée.
              </p>
              <p className="mt-3 text-text-secondary">
                À chaque connexion, le code de l&apos;application est demandé après le mot de passe. Codes de
                secours restants : <strong className="text-text">{info.recovery_codes_left}</strong> sur 10.
              </p>
              {info.recovery_codes_left <= 3 && (
                <p className="mt-2 text-[14px] text-error">
                  Il vous reste peu de codes de secours : générez-en de nouveaux.
                </p>
              )}
              <div className="mt-6 grid gap-6">
                <TotpRegenerate />
                <TotpDisable />
              </div>
            </>
          ) : (
            <>
              <p className="text-text-secondary">
                Aujourd&apos;hui, un code reçu par e-mail confirme chaque connexion. Une application
                d&apos;authentification (Google Authenticator, Microsoft Authenticator, 2FAS…) est plus sûre :
                elle fonctionne sans réseau et ne dépend pas de votre boîte mail.
              </p>
              <TotpEnroll />
            </>
          )}
        </Card>

        <Card>
          <CardTitle icon={<MonitorSmartphone size={18} aria-hidden="true" />}>Sessions ouvertes</CardTitle>
          <ul className="divide-y divide-border">
            {sessions.items.map((s) => (
              <li key={s.id} className="flex items-center justify-between gap-4 py-3">
                <div className="min-w-0">
                  <p className="font-semibold">
                    {s.device_name || browserName(s.user_agent)}
                    {s.current && (
                      <span className="ml-2 rounded-full bg-secondary-soft px-2 py-0.5 text-[12px] text-tertiary">
                        Cette session
                      </span>
                    )}
                  </p>
                  <p className="text-[13px] text-text-muted">
                    {s.app ? `App ${s.app} · ` : ""}dernière activité {formatDateTime(s.last_used_at)}
                  </p>
                </div>
                {!s.current && (
                  <ActionForm
                    action={revokeSession}
                    label="Déconnecter"
                    variant="outline"
                    hidden={{ id: s.id }}
                    confirm={{
                      title: "Déconnecter cette session ?",
                      body: "L'appareil devra se reconnecter avec le mot de passe et la double vérification.",
                    }}
                  />
                )}
              </li>
            ))}
          </ul>
          <p className="mt-4 flex items-start gap-2 text-[13px] text-text-muted">
            <KeyRound size={15} aria-hidden="true" className="mt-0.5 shrink-0" />
            Une session inconnue ? Déconnectez-la, puis changez votre mot de passe.
          </p>
        </Card>
      </div>
    </>
  );
}

/** Nom lisible du navigateur à partir de l'en-tête User-Agent. */
function browserName(ua: string): string {
  if (/Edg\//.test(ua)) return "Microsoft Edge";
  if (/Chrome\//.test(ua)) return "Chrome";
  if (/Firefox\//.test(ua)) return "Firefox";
  if (/Safari\//.test(ua)) return "Safari";
  return "Navigateur";
}
