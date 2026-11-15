"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

const LABEL: Record<string, string> = {
  accept: "Commande acceptée",
  reject: "Commande refusée",
  preparing: "Préparation commencée",
  ready: "Commande prête",
  handover: "Commande remise au client",
  "confirm-return": "Retour confirmé",
};

/** Action du back-office sur une commande d'une boutique gérée par ivia (journalisée). */
export async function orderAction(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id") ?? "");
  const action = String(form.get("action") ?? "");
  try {
    await api(`/v1/admin/platform-orders/${id}/${action}`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? ""), code: String(form.get("code") ?? "").trim() },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/ivi-orders");
  return { ok: true, message: LABEL[action] ?? "Fait." };
}

/** Confie une boutique au back-office (ou la rend à son compte marchand). */
export async function setManaged(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id") ?? "");
  const managed = form.get("managed") === "true";
  try {
    await api(`/v1/admin/shops/${id}/platform-managed`, { method: "POST", body: { managed } });
  } catch (err) {
    return failure(err);
  }
  revalidatePath(`/shops/${id}`);
  revalidatePath("/ivi-orders");
  return {
    ok: true,
    message: managed
      ? "Ses commandes arrivent désormais dans Commandes IVI."
      : "Boutique rendue à son marchand.",
  };
}
