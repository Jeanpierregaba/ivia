"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

/** Donne ou retire le rôle admin (journalisé ; l'API refuse de retirer le dernier admin). */
export async function setAdmin(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const grant = form.get("grant") === "true";
  try {
    await api(`/v1/admin/users/${encodeURIComponent(id)}/${grant ? "grant-admin" : "revoke-admin"}`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/users");
  return {
    ok: true,
    message: grant ? "Droits admin accordés." : "Droits admin retirés : l'accès au back-office est coupé.",
  };
}

/** Téléphone perdu sans code de secours : désactive l'application d'authentification d'un autre
 * admin et le déconnecte partout (motif obligatoire, journalisé). */
export async function resetMfa(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api(`/v1/admin/users/${encodeURIComponent(String(form.get("id")))}/mfa/reset`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/users");
  return { ok: true, message: "Double vérification réinitialisée : le code par e-mail sera demandé." };
}
