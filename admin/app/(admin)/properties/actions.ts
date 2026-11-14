"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { api, failure, type ActionResult, type Schemas } from "@/lib/api";
import { uploadImage } from "@/lib/upload";

function phone(v: FormDataEntryValue | null): string {
  const digits = String(v ?? "").replace(/\D/g, "");
  return digits.length === 8 ? `+228${digits}` : `+${digits}`;
}

function decimal(v: FormDataEntryValue | null): number {
  return Number(String(v ?? "").replace(",", "."));
}

function whole(v: FormDataEntryValue | null): number {
  return Number(String(v ?? "0").replace(/\s/g, "") || 0);
}

/** Crée l'annonce, ou la met à jour si le formulaire porte un identifiant. */
export async function saveProperty(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id") ?? "");
  let created = "";
  try {
    const keys = form.getAll("keep_photo").map(String);
    for (const f of form.getAll("new_photos")) {
      const key = await uploadImage(f, "property_photo");
      if (key) keys.push(key);
    }
    const body: Schemas["AdminPropertyInput"] = {
      title: String(form.get("title") ?? ""),
      kind: String(form.get("kind")) as Schemas["AdminPropertyInput"]["kind"],
      property_type: String(form.get("property_type")) as Schemas["AdminPropertyInput"]["property_type"],
      price_xof: whole(form.get("price_xof")),
      bedrooms: whole(form.get("bedrooms")),
      surface_m2: whole(form.get("surface_m2")),
      neighborhood: String(form.get("neighborhood") ?? ""),
      address_text: String(form.get("address_text") ?? ""),
      lat: decimal(form.get("lat")),
      lng: decimal(form.get("lng")),
      description: String(form.get("description") ?? ""),
      photo_keys: keys,
      contact_name: String(form.get("contact_name") ?? ""),
      contact_phone: phone(form.get("contact_phone")),
      is_active: form.get("is_active") === "on",
    };
    if (id) {
      await api(`/v1/admin/properties/${encodeURIComponent(id)}`, { method: "PUT", body });
    } else {
      created = (await api<{ id: string }>("/v1/admin/properties", { method: "POST", body })).id;
    }
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/properties");
  if (created) redirect(`/properties/${created}`);
  revalidatePath(`/properties/${id}`);
  return { ok: true, message: "Annonce enregistrée (action journalisée)." };
}

export async function setPropertyActive(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const active = String(form.get("is_active")) === "true";
  try {
    await api(`/v1/admin/properties/${encodeURIComponent(id)}/active`, {
      method: "PUT",
      body: { is_active: active, reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/properties");
  revalidatePath(`/properties/${id}`);
  return { ok: true, message: active ? "Annonce publiée." : "Annonce retirée de l'app." };
}
