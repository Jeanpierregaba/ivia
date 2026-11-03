import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { api, ApiError, sessionToken, type Schemas } from "@/lib/api";
import { AuthShell } from "../auth-shell";
import { CodeForm } from "./code-form";

export const metadata: Metadata = { title: "Code de vérification" };

// Maquette B02 : code à 6 chiffres reçu par e-mail, après le mot de passe.
export default async function CodePage() {
  if (!(await sessionToken())) redirect("/login");
  let me: Schemas["User"];
  let session: Schemas["SessionInfo"];
  try {
    [me, session] = await Promise.all([
      api<Schemas["User"]>("/v1/me"),
      api<Schemas["SessionInfo"]>("/v1/auth/session"),
    ]);
  } catch (err) {
    if (err instanceof ApiError) redirect("/logout");
    throw err;
  }
  if (session.mfa_verified) redirect("/");

  return (
    <AuthShell>
      <CodeForm email={me.email ?? ""} />
    </AuthShell>
  );
}
