"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

// Actions admin sur une commande, toutes journalisées par l'API.
const ACTIONS: Record<string, { path: string; done: string }> = {
  cancel: {
    path: "cancel",
    done: "Commande annulée. Si elle était payée, elle est dans la file de remboursement.",
  },
  "unlock-handover": { path: "unlock-handover", done: "Code de remise débloqué." },
  "confirm-return": {
    path: "confirm-return",
    done: "Retour confirmé : le livreur est libéré, la commande part en remboursement.",
  },
  "unassign-driver": { path: "unassign-driver", done: "Livreur retiré : la recherche d'un livreur reprend." },
  refund: {
    path: "refund",
    done: "Remboursement lancé. La commande passera à « Remboursée » à la confirmation du transfert.",
  },
};

export async function orderAction(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const action = ACTIONS[String(form.get("action"))];
  if (!action) return { ok: false, message: "Action inconnue." };
  try {
    await api(`/v1/admin/orders/${encodeURIComponent(id)}/${action.path}`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath(`/orders/${id}`);
  revalidatePath("/orders");
  revalidatePath("/refunds");
  return { ok: true, message: action.done };
}
