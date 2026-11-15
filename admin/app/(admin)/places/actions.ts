"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

function decimal(v: FormDataEntryValue | null): number {
  return Number(String(v ?? "").replace(",", "."));
}

export async function savePlace(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id") ?? "");
  const body = {
    name: String(form.get("name") ?? ""),
    category: String(form.get("category") ?? ""),
    address: String(form.get("address") ?? ""),
    aliases: String(form.get("aliases") ?? "")
      .split(/[;,]/)
      .map((a) => a.trim())
      .filter(Boolean),
    location: { lat: decimal(form.get("lat")), lng: decimal(form.get("lng")) },
    is_active: id ? form.get("is_active") === "on" : true,
  };
  try {
    await api(id ? `/v1/admin/places/${encodeURIComponent(id)}` : "/v1/admin/places", {
      method: id ? "PUT" : "POST",
      body,
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/places");
  return { ok: true, message: "Lieu enregistré (action journalisée)." };
}

export async function saveZone(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id") ?? "");
  let geojson: unknown;
  try {
    geojson = JSON.parse(String(form.get("geojson") ?? ""));
  } catch {
    return { ok: false, message: "Polygone illisible : collez un GeoJSON valide." };
  }
  const n = (name: string) => Number(form.get(name) || 0);
  const body = {
    name: String(form.get("name") ?? ""),
    type: String(form.get("type")),
    is_active: form.get("is_active") === "on",
    geojson,
    rules: {
      base_xof: n("base_xof"),
      per_km_xof: n("per_km_xof"),
      per_min_xof: n("per_min_xof"),
      multiplier: n("multiplier"),
    },
  };
  try {
    await api(id ? `/v1/admin/zones/${encodeURIComponent(id)}` : "/v1/admin/zones", {
      method: id ? "PUT" : "POST",
      body,
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/zones");
  return { ok: true, message: "Zone enregistrée (action journalisée)." };
}

export async function deleteZone(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api(`/v1/admin/zones/${encodeURIComponent(String(form.get("id")))}`, { method: "DELETE" });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/zones");
  return { ok: true, message: "Zone retirée." };
}
