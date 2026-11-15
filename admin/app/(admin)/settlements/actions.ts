"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { api, failure, type ActionResult, type Schemas } from "@/lib/api";

/** Crée le relevé prévisualisé, puis ouvre sa fiche. */
export async function createSettlement(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  let created: Schemas["Settlement"];
  try {
    created = await api<Schemas["Settlement"]>("/v1/admin/settlements", {
      method: "POST",
      body: {
        shop_id: String(form.get("shop_id")),
        period_start: String(form.get("from")),
        period_end: String(form.get("to")),
        note: String(form.get("reason") ?? ""),
      },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/settlements");
  redirect(`/settlements/${created.id}`);
}

/** Marque un relevé comme réglé, avec la référence du virement Mobile Money ou bancaire. */
export async function markSettled(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  try {
    await api(`/v1/admin/settlements/${encodeURIComponent(id)}/mark-settled`, {
      method: "POST",
      body: {
        settlement_reference: String(form.get("settlement_reference") ?? "").trim(),
        note: String(form.get("note") ?? ""),
      },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/settlements", "layout");
  return { ok: true, message: "Relevé marqué comme réglé." };
}

/** Supprime un relevé encore ouvert : ses commandes redeviennent disponibles pour un autre relevé. */
export async function deleteSettlement(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  try {
    await api(`/v1/admin/settlements/${encodeURIComponent(id)}`, {
      method: "DELETE",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/settlements");
  redirect("/settlements");
}
