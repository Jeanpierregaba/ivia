"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { api, ApiError, SESSION_COOKIE, type Schemas } from "@/lib/api";

// Connexion au back-office (ADR 0011, ADR 0012) : e-mail et mot de passe (B01), puis second facteur
// (B02) : code de l'application d'authentification si elle est activée, sinon code reçu par e-mail. Entre les deux, la session existe mais n'ouvre aucune route admin (mfa_required) ; son
// cookie ne vit que 15 minutes. Le jeton reste dans un cookie httpOnly, jamais dans le navigateur.

export type FormState = { error?: string; fields?: Record<string, string>; info?: string };

const secure = process.env.NODE_ENV === "production";

async function setSessionCookie(token: string, expires?: Date) {
  (await cookies()).set(SESSION_COOKIE, token, {
    httpOnly: true,
    secure,
    sameSite: "lax",
    path: "/",
    expires,
  });
}

async function revoke(token: string) {
  await fetch(`${process.env.API_BASE_URL}/v1/auth/logout`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(5_000),
  }).catch(() => undefined);
}

/** Ouvre la session à vérifier : rôle admin exigé, puis envoi du code de double vérification. */
async function startVerification(session: Schemas["Session"]): Promise<FormState | undefined> {
  if (!session.user.roles.includes("admin")) {
    await revoke(session.token); // compte sans rôle admin : session aussitôt révoquée
    return { error: "Ce compte n'a pas accès au back-office." };
  }
  await setSessionCookie(session.token, new Date(Date.now() + 15 * 60 * 1000));
  try {
    // Application d'authentification activée : aucun e-mail à envoyer.
    const info = await api<Schemas["SessionInfo"]>("/v1/auth/session");
    if (info.mfa_method === "totp") return undefined;
    await api("/v1/auth/mfa/code", { method: "POST" });
  } catch (err) {
    if (err instanceof ApiError && err.code !== "otp_rate_limited") return { error: err.message };
    if (!(err instanceof ApiError)) throw err;
  }
  return undefined;
}

/** B01 : e-mail et mot de passe. */
export async function passwordLogin(_: FormState, form: FormData): Promise<FormState> {
  let session: Schemas["Session"];
  try {
    session = await api<Schemas["Session"]>("/v1/auth/login", {
      method: "POST",
      anonymous: true,
      body: { email: String(form.get("email") ?? "").trim(), password: String(form.get("password") ?? "") },
    });
  } catch (err) {
    if (err instanceof ApiError) return { error: err.message, fields: err.fields };
    throw err;
  }
  const failed = await startVerification(session);
  if (failed) return failed;
  redirect("/login/code");
}

/** B02 : code reçu par e-mail ; « Rester connecté 8 heures » rend le cookie persistant. */
export async function verifyCode(_: FormState, form: FormData): Promise<FormState> {
  let info: Schemas["SessionInfo"];
  try {
    info = await api<Schemas["SessionInfo"]>("/v1/auth/mfa/verify", {
      method: "POST",
      body: { code: secondFactorCode(String(form.get("code") ?? "")) },
    });
  } catch (err) {
    if (err instanceof ApiError) return { error: err.message };
    throw err;
  }
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!token) redirect("/login");
  // Sans « rester connecté », cookie de session : il disparaît à la fermeture du navigateur.
  await setSessionCookie(token, form.get("remember") === "on" ? new Date(info.expires_at) : undefined);
  redirect("/");
}

/** Code à 6 chiffres (espaces retirés) ou code de secours « XXXX-XXXX ». */
function secondFactorCode(raw: string): string {
  const trimmed = raw.trim();
  return /^[\d\s]+$/.test(trimmed) ? trimmed.replace(/\D/g, "") : trimmed.toUpperCase().replace(/\s/g, "");
}

/** B02 : nouveau code (1 par minute). */
export async function resendCode(): Promise<FormState> {
  try {
    await api("/v1/auth/mfa/code", { method: "POST" });
  } catch (err) {
    if (err instanceof ApiError) return { error: err.message };
    throw err;
  }
  return { info: "Nouveau code envoyé." };
}

/** B02 « Changer d'e-mail » : la session en attente est révoquée. */
export async function restart(): Promise<void> {
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value;
  if (token) await revoke(token);
  store.delete(SESSION_COOKIE);
  redirect("/login");
}

/** Mot de passe oublié, étape 1 : code envoyé à l'adresse (même réponse si elle est inconnue). */
export async function forgotPassword(_: FormState, form: FormData): Promise<FormState> {
  const email = String(form.get("email") ?? "").trim();
  try {
    await api("/v1/auth/password/forgot", { method: "POST", anonymous: true, body: { email } });
  } catch (err) {
    if (err instanceof ApiError) return { error: err.message, fields: err.fields };
    throw err;
  }
  return { info: email };
}

/** Mot de passe oublié, étape 2 : code et nouveau mot de passe, puis double vérification. */
export async function resetPassword(_: FormState, form: FormData): Promise<FormState> {
  let session: Schemas["Session"];
  try {
    session = await api<Schemas["Session"]>("/v1/auth/password/reset", {
      method: "POST",
      anonymous: true,
      body: {
        email: String(form.get("email") ?? "").trim(),
        code: String(form.get("code") ?? "").replace(/\D/g, ""),
        password: String(form.get("password") ?? ""),
      },
    });
  } catch (err) {
    if (err instanceof ApiError)
      return { error: err.message, fields: err.fields, info: String(form.get("email") ?? "") };
    throw err;
  }
  const failed = await startVerification(session);
  if (failed) return failed;
  redirect("/login/code");
}
