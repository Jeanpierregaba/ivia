"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { api, ApiError, SESSION_COOKIE, type Schemas } from "@/lib/api";

export type LoginState = {
  step: "email" | "code";
  email: string;
  error?: string;
  info?: string;
};

/**
 * Connexion en deux étapes, pilotée par le champ « step » du formulaire :
 * « email » envoie le code, « code » le vérifie et ouvre la session (rôle admin exigé).
 */
export async function login(prev: LoginState, form: FormData): Promise<LoginState> {
  if (form.getAll("step").includes("restart")) return { step: "email", email: prev.email };

  if (form.get("step") === "email") {
    const email = String(form.get("email") ?? "").trim();
    try {
      await api("/v1/auth/otp", {
        method: "POST",
        anonymous: true,
        body: { channel: "email", recipient: email },
      });
    } catch (err) {
      if (err instanceof ApiError)
        return { step: "email", email, error: err.fields.recipient ?? err.message };
      throw err;
    }
    return {
      step: "code",
      email,
      info: "Un code à 6 chiffres vient d'être envoyé. Il est valable 10 minutes.",
    };
  }

  const code = String(form.get("code") ?? "").trim();
  let session: Schemas["Session"];
  try {
    session = await api<Schemas["Session"]>("/v1/auth/verify", {
      method: "POST",
      anonymous: true,
      body: { channel: "email", recipient: prev.email, code },
    });
  } catch (err) {
    if (err instanceof ApiError) return { step: "code", email: prev.email, error: err.message };
    throw err;
  }

  if (!session.user.roles.includes("admin")) {
    // Compte sans rôle admin : la session tout juste ouverte est aussitôt révoquée.
    await fetch(`${process.env.API_BASE_URL}/v1/auth/logout`, {
      method: "POST",
      headers: { Authorization: `Bearer ${session.token}` },
      signal: AbortSignal.timeout(5_000),
    }).catch(() => undefined);
    return { step: "email", email: "", error: "Ce compte n'a pas accès au back-office." };
  }

  (await cookies()).set(SESSION_COOKIE, session.token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    expires: new Date(session.expires_at),
  });
  redirect("/");
}
