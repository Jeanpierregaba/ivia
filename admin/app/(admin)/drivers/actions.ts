"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult, type Schemas } from "@/lib/api";

const DECISIONS = ["approve", "reject", "suspend", "reinstate"] as const;
const DONE: Record<(typeof DECISIONS)[number], string> = {
  approve: "Livreur validé : il peut passer en ligne.",
  reject: "Candidature refusée.",
  suspend: "Livreur suspendu.",
  reinstate: "Livreur rétabli.",
};

function refresh(id: string) {
  revalidatePath("/drivers");
  revalidatePath(`/drivers/${id}`);
}

export async function reviewDriver(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const decision = String(form.get("decision")) as (typeof DECISIONS)[number];
  if (!DECISIONS.includes(decision)) return { ok: false, message: "Action inconnue." };
  try {
    await api(`/v1/admin/drivers/${encodeURIComponent(id)}/${decision}`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  refresh(id);
  return { ok: true, message: DONE[decision] };
}

const ACTIVITIES = ["delivery", "vtc"];
const ACTIVITY_DECISIONS = ["approve", "request-changes", "reject"] as const;
const ACTIVITY_DONE: Record<(typeof ACTIVITY_DECISIONS)[number], string> = {
  approve: "Activité validée : le partenaire est prévenu.",
  "request-changes": "Compléments demandés : le partenaire est prévenu avec le motif.",
  reject: "Dossier refusé : le partenaire est prévenu avec le motif.",
};

/** Décision du back-office sur une activité (livraison, taxi VTC). */
export async function reviewActivity(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const activity = String(form.get("activity"));
  const decision = String(form.get("decision")) as (typeof ACTIVITY_DECISIONS)[number];
  if (!ACTIVITIES.includes(activity) || !ACTIVITY_DECISIONS.includes(decision))
    return { ok: false, message: "Action inconnue." };
  try {
    await api(`/v1/admin/drivers/${encodeURIComponent(id)}/activities/${activity}/${decision}`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  refresh(id);
  return { ok: true, message: ACTIVITY_DONE[decision] };
}

/** Résultat du contrôle du véhicule sur place. */
export async function checkVehicle(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const activity = String(form.get("activity"));
  if (!ACTIVITIES.includes(activity)) return { ok: false, message: "Action inconnue." };
  const passed = form.get("passed") === "true";
  try {
    await api(`/v1/admin/drivers/${encodeURIComponent(id)}/activities/${activity}/vehicle-check`, {
      method: "POST",
      body: { passed, note: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  refresh(id);
  return { ok: true, message: passed ? "Véhicule conforme." : "Contrôle du véhicule non conforme enregistré." };
}

/** Réglages partenaires : ouverture du VTC, contrôle du véhicule en livraison, guide. */
export async function saveDriverSettings(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const body: Schemas["DriverSettings"] = {
    vtc_mode: String(form.get("vtc_mode")) as Schemas["DriverSettings"]["vtc_mode"],
    delivery_vehicle_check: form.get("delivery_vehicle_check") === "on",
    partner_guide: String(form.get("partner_guide") ?? ""),
  };
  try {
    await api("/v1/admin/driver-settings", { method: "PUT", body });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/driver-settings");
  return { ok: true, message: "Réglages enregistrés." };
}
