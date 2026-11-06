"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult, type Schemas } from "@/lib/api";

const REVIEW_DONE: Record<string, string> = {
  approve: "Pharmacie validée : elle peut recevoir les alertes.",
  reject: "Dossier refusé : le motif est envoyé au titulaire.",
  suspend: "Pharmacie suspendue.",
  reinstate: "Pharmacie rétablie.",
};

export async function reviewPharmacy(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const decision = String(form.get("decision"));
  if (!(decision in REVIEW_DONE)) return { ok: false, message: "Action inconnue." };
  try {
    await api(`/v1/admin/pharmacies/${encodeURIComponent(id)}/review`, {
      method: "POST",
      body: { decision, reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/pharmacies");
  revalidatePath(`/pharmacies/${id}`);
  return { ok: true, message: REVIEW_DONE[decision] ?? "Décision enregistrée." };
}

/** Saisie du formulaire (heure de Lomé, soit UTC) vers ISO 8601. */
function iso(v: FormDataEntryValue | null): string | null {
  const s = String(v ?? "").trim();
  if (!s) return null;
  const d = new Date(s + ":00Z");
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

export async function addDutyShift(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const starts = iso(form.get("starts_at"));
  const ends = iso(form.get("ends_at"));
  if (!starts || !ends) return { ok: false, message: "Indiquez le début et la fin de la garde." };
  try {
    await api(`/v1/admin/pharmacies/${encodeURIComponent(id)}/duty-shifts`, {
      method: "POST",
      body: { starts_at: starts, ends_at: ends, reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath(`/pharmacies/${id}`);
  return { ok: true, message: "Garde ajoutée au planning." };
}

export async function deleteDutyShift(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const pharmacy = String(form.get("pharmacy_id"));
  try {
    await api(`/v1/admin/pharmacy-duty-shifts/${encodeURIComponent(String(form.get("id")))}`, {
      method: "DELETE",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath(`/pharmacies/${pharmacy}`);
  return { ok: true, message: "Garde retirée du planning." };
}

export async function recordPayout(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const amount = Number(String(form.get("amount_xof") ?? "").replace(/\s/g, ""));
  if (!Number.isInteger(amount) || amount <= 0) return { ok: false, message: "Montant en FCFA entiers." };
  try {
    await api(`/v1/admin/pharmacies/${encodeURIComponent(id)}/payouts`, {
      method: "POST",
      body: {
        amount_xof: amount,
        reference: String(form.get("reference") ?? ""),
        note: String(form.get("note") ?? ""),
      },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath(`/pharmacies/${id}`);
  return { ok: true, message: "Reversement enregistré (action journalisée)." };
}

function medicineBody(form: FormData, active: boolean): Schemas["MedicineInput"] {
  return {
    name: String(form.get("name") ?? ""),
    dosage: String(form.get("dosage") ?? ""),
    form: String(form.get("form") ?? ""),
    active_ingredient: String(form.get("active_ingredient") ?? ""),
    is_active: active,
  } as Schemas["MedicineInput"];
}

export async function createMedicine(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api("/v1/admin/medicines", { method: "POST", body: medicineBody(form, true) });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/medicines");
  return { ok: true, message: "Médicament ajouté à la base." };
}

export async function toggleMedicine(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const active = String(form.get("is_active")) === "true";
  try {
    await api(`/v1/admin/medicines/${encodeURIComponent(String(form.get("id")))}`, {
      method: "PATCH",
      body: medicineBody(form, active),
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/medicines");
  return { ok: true, message: active ? "Médicament réactivé." : "Médicament retiré des suggestions." };
}

export async function refundMedicinePayment(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api(`/v1/admin/medicine-payments/${encodeURIComponent(String(form.get("id")))}/refund`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/medicine-payments");
  revalidatePath("/medicine-alerts");
  return { ok: true, message: "Remboursement lancé (action journalisée)." };
}

export async function savePharmacySettings(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const n = (name: string) => Number(form.get(name));
  const radii = String(form.get("radius_options_m") ?? "")
    .split(/[,;\s]+/)
    .filter(Boolean)
    .map(Number);
  if (radii.some((r) => !Number.isInteger(r) || r <= 0))
    return { ok: false, message: "Rayons proposés : des nombres entiers de mètres, séparés par des virgules." };
  const body: Schemas["PharmacySettingsInput"] = {
    enabled: form.get("enabled") === "on",
    auto_widen: form.get("auto_widen") === "on",
    unlock_fee_xof: n("unlock_fee_xof"),
    search_radius_m: n("search_radius_m"),
    max_radius_m: n("max_radius_m"),
    radius_options_m: radii,
    target_responses: n("target_responses"),
    widen_after_minutes: n("widen_after_minutes"),
    response_window_minutes: n("response_window_minutes"),
    pickup_hold_minutes: n("pickup_hold_minutes"),
    photo_retention_hours: n("photo_retention_hours"),
    product_commission_bp: n("product_commission_bp"),
    reason: String(form.get("reason") ?? ""),
  };
  try {
    await api("/v1/admin/pharmacy/settings", { method: "PUT", body });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/pharmacy-settings");
  return { ok: true, message: "Réglages enregistrés (action journalisée)." };
}
