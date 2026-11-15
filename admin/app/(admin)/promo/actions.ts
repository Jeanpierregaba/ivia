"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { api, failure, type ActionResult, type Schemas } from "@/lib/api";
import { uploadImage } from "@/lib/upload";

type VisualInput = Schemas["PromoVisualInput"];

// Date « jj/mm/aaaa hh:mm » du champ datetime-local (heure de Lomé = UTC) vers RFC 3339.
function dateOrNull(v: FormDataEntryValue | null): string | null {
  const s = String(v ?? "").trim();
  return s ? new Date(s + ":00Z").toISOString() : null;
}

function visualFrom(form: FormData, imageKey: string): VisualInput {
  const product = String(form.get("product_id") ?? "").trim();
  return {
    kind: String(form.get("kind")) as VisualInput["kind"],
    title: String(form.get("title") ?? ""),
    subtitle: String(form.get("subtitle") ?? ""),
    body: String(form.get("body") ?? ""),
    image_key: imageKey,
    product_id: product || null,
    cta_label: String(form.get("cta_label") ?? ""),
    external_url: String(form.get("external_url") ?? ""),
    placements: form.getAll("placements").map(String) as VisualInput["placements"],
    apps: form.getAll("apps").map(String) as VisualInput["apps"],
    priority: Number(form.get("priority") ?? 0),
    weight: Number(form.get("weight") ?? 1),
    starts_at: dateOrNull(form.get("starts_at")),
    ends_at: dateOrNull(form.get("ends_at")),
    is_active: form.get("is_active") === "on",
  };
}

export async function saveVisual(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id") ?? "");
  let saved: Schemas["PromoVisual"];
  try {
    const key = (await uploadImage(form.get("image"), "promo_visual")) ?? String(form.get("image_key") ?? "");
    if (!key) return { ok: false, message: "Ajoutez l'image du visuel." };
    const body = visualFrom(form, key);
    saved = id
      ? await api(`/v1/admin/promo/visuals/${id}`, { method: "PATCH", body })
      : await api("/v1/admin/promo/visuals", { method: "POST", body });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/promo");
  if (!id) redirect(`/promo/visuals/${saved.id}?created=1`);
  revalidatePath(`/promo/visuals/${id}`);
  return { ok: true, message: "Visuel enregistré : il part dans les apps au prochain chargement." };
}

export async function toggleVisual(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  try {
    const v = await api<Schemas["PromoVisual"]>(`/v1/admin/promo/visuals/${id}`);
    const body: VisualInput = {
      kind: v.kind,
      title: v.title,
      subtitle: v.subtitle,
      body: v.body,
      image_key: v.image_key,
      product_id: v.product_id,
      cta_label: v.cta_label,
      external_url: v.external_url,
      placements: v.placements,
      apps: v.apps,
      priority: v.priority,
      weight: v.weight,
      starts_at: v.starts_at,
      ends_at: v.ends_at,
      is_active: !v.is_active,
    };
    await api(`/v1/admin/promo/visuals/${id}`, { method: "PATCH", body });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/promo");
  return { ok: true, message: "Diffusion mise à jour." };
}

export async function deleteVisual(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  try {
    await api(`/v1/admin/promo/visuals/${String(form.get("id"))}`, { method: "DELETE" });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/promo");
  redirect("/promo");
}

export async function saveSettings(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const num = (k: string) => Number(form.get(k) ?? 0);
  const body: Schemas["PromoSettings"] = {
    enabled: form.get("enabled") === "on",
    banners_enabled: form.get("banners_enabled") === "on",
    modal_enabled: form.get("modal_enabled") === "on",
    interstitial_enabled: form.get("interstitial_enabled") === "on",
    first_delay_seconds: num("first_delay_seconds"),
    min_interval_seconds: num("min_interval_seconds"),
    max_per_session: num("max_per_session"),
    feed_every: num("feed_every"),
    rotation: String(form.get("rotation")) as Schemas["PromoSettings"]["rotation"],
    official_url: String(form.get("official_url") ?? ""),
  };
  try {
    await api("/v1/admin/promo/settings", { method: "PUT", body });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/promo");
  return { ok: true, message: "Réglages enregistrés : appliqués par les apps à leur prochain chargement." };
}
