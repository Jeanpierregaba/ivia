"use server";

import { revalidatePath } from "next/cache";

import { api, ApiError, failure, type ActionResult, type Schemas } from "@/lib/api";

// Sécurité du compte admin (ADR 0012) : application d'authentification, codes de secours, sessions.
// Le secret et les codes de secours ne transitent que dans la réponse de l'action, jamais dans une
// URL, et ne sont gardés ni dans un cookie ni dans le navigateur.

export type TotpSetupResult = { ok: true; secret: string; uri: string } | { ok: false; message: string };

export type CodesResult = { ok: true; codes: string[] } | { ok: false; message: string } | null;

const code6 = (form: FormData) => String(form.get("code") ?? "").replace(/\D/g, "");

/** Étape 1 : nouveau secret à scanner. */
export async function startTotp(): Promise<TotpSetupResult> {
  try {
    const out = await api<Schemas["TOTPSetup"]>("/v1/auth/mfa/totp/setup", { method: "POST" });
    return { ok: true, secret: out.secret, uri: out.otpauth_uri };
  } catch (err) {
    if (err instanceof ApiError) return { ok: false, message: err.message };
    throw err;
  }
}

/** Étape 2 : premier code de l'application ; retourne les 10 codes de secours. */
export async function confirmTotp(_: CodesResult, form: FormData): Promise<CodesResult> {
  try {
    const out = await api<Schemas["RecoveryCodes"]>("/v1/auth/mfa/totp/confirm", {
      method: "POST",
      body: { code: code6(form) },
    });
    revalidatePath("/security");
    return { ok: true, codes: out.recovery_codes };
  } catch (err) {
    if (err instanceof ApiError) return { ok: false, message: err.message };
    throw err;
  }
}

/** Nouveaux codes de secours (les anciens ne servent plus). */
export async function regenerateCodes(_: CodesResult, form: FormData): Promise<CodesResult> {
  try {
    const out = await api<Schemas["RecoveryCodes"]>("/v1/auth/mfa/totp/recovery-codes", {
      method: "POST",
      body: { code: code6(form) },
    });
    revalidatePath("/security");
    return { ok: true, codes: out.recovery_codes };
  } catch (err) {
    if (err instanceof ApiError) return { ok: false, message: err.message };
    throw err;
  }
}

/** Désactive l'application : le code par e-mail redevient le second facteur. */
export async function disableTotp(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api("/v1/auth/mfa/totp/disable", { method: "POST", body: { code: code6(form) } });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/security");
  return { ok: true, message: "Application désactivée : le code par e-mail est de nouveau demandé." };
}

/** Déconnecte une autre session du compte. */
export async function revokeSession(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api(`/v1/me/sessions/${encodeURIComponent(String(form.get("id")))}`, { method: "DELETE" });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/security");
  return { ok: true, message: "Session déconnectée." };
}
