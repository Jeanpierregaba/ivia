"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

const int = (form: FormData, k: string): number | undefined => {
  const raw = String(form.get(k) ?? "").replace(/\s/g, "");
  if (raw === "") return undefined;
  const n = Number(raw);
  return Number.isInteger(n) ? n : NaN;
};

/** Code pour une boutique (boutique IVI), à sa charge, journalisé. */
export async function createCode(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const kind = String(form.get("kind") ?? "percent");
  const days = int(form, "days");
  const body = {
    code: String(form.get("code") ?? ""),
    shop_id: String(form.get("shop_id") ?? "") || undefined,
    kind,
    value: int(form, "value"),
    max_discount_xof: kind === "percent" ? int(form, "max_discount_xof") : undefined,
    min_order_xof: int(form, "min_order_xof") ?? 0,
    max_uses: int(form, "max_uses"),
    max_uses_per_user: int(form, "max_uses_per_user") ?? 1,
    visibility: form.get("private") ? "private" : "public",
    ends_at: days ? new Date(Date.now() + days * 86_400_000).toISOString() : undefined,
    product_ids: form.get("scope") === "products" ? form.getAll("product_ids").map(String) : undefined,
  };
  if (form.get("scope") === "products" && !body.product_ids?.length)
    return { ok: false, message: "Choisissez au moins un produit." };
  if (Object.values(body).some((v) => typeof v === "number" && Number.isNaN(v)))
    return { ok: false, message: "Nombres entiers uniquement." };
  let code: string;
  try {
    code = (await api<{ code: string }>("/v1/admin/promo-codes", { method: "POST", body })).code;
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/coupons");
  return { ok: true, message: `Code ${code} créé (action journalisée).` };
}

/** Suspendre (motif obligatoire), reprendre ou terminer un code. */
export async function codeAction(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const id = String(form.get("id") ?? "");
  const action = String(form.get("action") ?? "");
  try {
    await api(`/v1/admin/promo-codes/${id}/${action}`, {
      method: "POST",
      body: { reason: String(form.get("reason") ?? "") },
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/coupons");
  const done = { suspend: "suspendu", resume: "repris", end: "terminé" }[action] ?? "modifié";
  return { ok: true, message: `Code ${done} (action journalisée).` };
}

/** Réglages du coupon de bienvenue offert par ivia. */
export async function updateWelcome(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const body = {
    welcome_enabled: form.get("welcome_enabled") === "on",
    welcome_amount_xof: int(form, "welcome_amount_xof") ?? 0,
    welcome_min_order_xof: int(form, "welcome_min_order_xof") ?? 0,
    welcome_valid_days: int(form, "welcome_valid_days") ?? 30,
  };
  if (Object.values(body).some((v) => typeof v === "number" && Number.isNaN(v)))
    return { ok: false, message: "Nombres entiers uniquement." };
  try {
    await api("/v1/admin/coupon-settings", { method: "PUT", body });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/coupons");
  return { ok: true, message: "Coupon de bienvenue enregistré (action journalisée)." };
}
