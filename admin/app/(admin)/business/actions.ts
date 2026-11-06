"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

const DONE: Record<string, string> = {
  approve: "Espace activé : le marchand est prévenu.",
  needs_changes: "Compléments demandés au marchand.",
  reject: "Dossier refusé : le motif est envoyé au marchand.",
  suspend: "Espace suspendu.",
  reinstate: "Espace rétabli.",
};

export async function reviewSpace(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const decision = String(form.get("decision"));
  if (!(decision in DONE)) return { ok: false, message: "Action inconnue." };
  try {
    await api(`/v1/admin/business/spaces/${encodeURIComponent(id)}/review`, {
      method: "POST",
      body: { decision, reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/business");
  revalidatePath(`/business/${id}`);
  return { ok: true, message: DONE[decision] ?? "Décision enregistrée." };
}
