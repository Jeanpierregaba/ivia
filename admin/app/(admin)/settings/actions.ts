"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

const SETTING_FIELDS = [
  "commission_rate_bp",
  "motorbike_base_fee_xof",
  "motorbike_per_km_xof",
  "car_base_fee_xof",
  "car_per_km_xof",
  "distance_coefficient_pct",
  "payment_timeout_minutes",
  "seller_response_timeout_minutes",
  "driver_offer_timeout_seconds",
  "assignment_max_offers",
  "assignment_alert_minutes",
] as const;

export async function updateSettings(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const body: Record<string, number | string> = { reason: String(form.get("reason") ?? "") };
  for (const f of SETTING_FIELDS) {
    const raw = String(form.get(f) ?? "").trim();
    if (raw === "") continue;
    const n = Number(raw);
    if (!Number.isInteger(n))
      return { ok: false, message: "Valeurs entières uniquement (pas de décimales)." };
    body[f] = n;
  }
  try {
    await api("/v1/admin/settings", { method: "PATCH", body });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/settings");
  return { ok: true, message: "Paramètres enregistrés (action journalisée)." };
}
