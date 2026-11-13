"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

/** Crée un compte admin avec son rôle (journalisé). */
export async function createAdmin(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const body = {
    email: String(form.get("email") ?? "").trim(),
    first_name: String(form.get("first_name") ?? ""),
    last_name: String(form.get("last_name") ?? ""),
    role: String(form.get("role") ?? ""),
  };
  try {
    await api("/v1/admin/admins", { method: "POST", body });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/admins");
  return {
    ok: true,
    message: `Compte créé : ${body.email} choisit son mot de passe avec « Mot de passe oublié » sur la page de connexion.`,
  };
}

/** Change le rôle d'un compte admin (journalisé). */
export async function setRole(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api(`/v1/admin/admins/${encodeURIComponent(String(form.get("id")))}/role`, {
      method: "PUT",
      body: { role: String(form.get("role") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/admins");
  return { ok: true, message: "Rôle modifié : il s'applique dès sa prochaine page." };
}

/** Retire l'accès au back-office (journalisé). */
export async function removeAdmin(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api(`/v1/admin/admins/${encodeURIComponent(String(form.get("id")))}`, { method: "DELETE" });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/admins");
  return { ok: true, message: "Accès au back-office retiré." };
}
