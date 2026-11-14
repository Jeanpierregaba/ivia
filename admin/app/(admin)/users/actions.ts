"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

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
