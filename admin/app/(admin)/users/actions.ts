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
