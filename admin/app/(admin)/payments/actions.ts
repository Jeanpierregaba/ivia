"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

/** Revérifie un paiement en attente auprès du prestataire. */
export async function verifyPayment(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  try {
    const p = await api<{ status: string }>(`/v1/admin/payments/${encodeURIComponent(id)}/verify`, {
      method: "POST",
    });
    revalidatePath("/payments");
    return {
      ok: true,
      message: p.status === "pending" ? "Toujours en attente chez le prestataire." : "Statut mis à jour.",
    };
  } catch (err) {
    return failure(err);
  }
}

/** Rembourse un paiement reçu en double (l'API refuse tout autre paiement). */
export async function refundDuplicate(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  try {
    await api(`/v1/admin/payments/${encodeURIComponent(id)}/refund`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/payments");
  return { ok: true, message: "Remboursement du doublon lancé." };
}
