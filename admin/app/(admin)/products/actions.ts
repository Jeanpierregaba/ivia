"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult, type Schemas } from "@/lib/api";
import { uploadImage } from "@/lib/upload";

function dateOrNull(v: FormDataEntryValue | null): string | null {
  const s = String(v ?? "").trim();
  return s ? new Date(s + ":00Z").toISOString() : null;
}

function done(id: string, message: string): ActionResult {
  revalidatePath(`/products/${id}`);
  revalidatePath("/products");
  revalidatePath("/promo");
  return { ok: true, message };
}

/** Fiche produit : nom, description, catégorie, prix, colis, mise en vente et photos. */
export async function saveProduct(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const price = Number(String(form.get("price_xof") ?? "").replace(/\s/g, "") || 0);
  if (!Number.isInteger(price) || price < 0) return { ok: false, message: "Prix en FCFA entiers." };
  try {
    const keys = form.getAll("keep_image").map(String);
    for (const f of form.getAll("new_images")) {
      const key = await uploadImage(f, "product_image");
      if (key) keys.push(key);
    }
    const body: Schemas["ProductInput"] = {
      category_id: String(form.get("category_id")),
      name: String(form.get("name") ?? ""),
      description: String(form.get("description") ?? ""),
      price_xof: price,
      parcel_size: String(form.get("parcel_size")) as Schemas["ProductInput"]["parcel_size"],
      is_active: form.get("is_active") === "on",
      image_keys: keys.slice(0, 6),
    };
    await api(`/v1/admin/products/${id}`, { method: "PATCH", body });
  } catch (err) {
    return failure(err);
  }
  return done(id, "Produit enregistré (action journalisée).");
}

export async function saveStock(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const quantity = Number(form.get("quantity"));
  if (!Number.isInteger(quantity) || quantity < 0)
    return { ok: false, message: "Quantité entière attendue." };
  try {
    await api(`/v1/admin/products/${id}/stock`, {
      method: "PUT",
      body: { quantity, note: String(form.get("note") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  return done(id, "Stock mis à jour.");
}

/** Promotion, badges, mise en avant et caractéristiques. */
export async function saveMarketing(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id"));
  const promoRaw = String(form.get("promo_price_xof") ?? "").replace(/\s/g, "");
  const rankRaw = String(form.get("featured_rank") ?? "").trim();
  const body: Schemas["ProductMarketingInput"] = {
    promo_price_xof: promoRaw ? Number(promoRaw) : null,
    promo_starts_at: dateOrNull(form.get("promo_starts_at")),
    promo_ends_at: dateOrNull(form.get("promo_ends_at")),
    badges: form.getAll("badges").map(String) as Schemas["ProductMarketingInput"]["badges"],
    featured_rank: rankRaw ? Number(rankRaw) : null,
    features: String(form.get("features") ?? "")
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean),
  };
  try {
    await api(`/v1/admin/products/${id}/marketing`, { method: "PUT", body });
  } catch (err) {
    return failure(err);
  }
  return done(id, "Promotion et mise en avant enregistrées : visibles dans les apps.");
}
