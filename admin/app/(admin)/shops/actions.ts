"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

const DECISIONS = ["approve", "reject", "suspend", "reinstate"] as const;
const DONE: Record<(typeof DECISIONS)[number], string> = {
  approve: "Boutique publiée.",
  reject: "Boutique refusée.",
  suspend: "Boutique suspendue.",
  reinstate: "Boutique rétablie.",
};

export async function reviewShop(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const decision = String(form.get("decision")) as (typeof DECISIONS)[number];
  if (!DECISIONS.includes(decision)) return { ok: false, message: "Action inconnue." };
  try {
    await api(`/v1/admin/shops/${encodeURIComponent(id)}/${decision}`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/shops");
  return { ok: true, message: DONE[decision] };
}
