"use server";

import { revalidatePath } from "next/cache";

import { api, failure, type ActionResult } from "@/lib/api";

// Ajout (sans id) ou modification (avec id) d'une entrée de référentiel, journalisés par l'API.
// Désactiver plutôt que supprimer : les boutiques et produits existants gardent leur rattachement.

const KINDS = {
  categories: { path: "/v1/admin/categories", done: "Catégorie de produits" },
  "shop-categories": { path: "/v1/admin/shop-categories", done: "Catégorie de boutique" },
  neighborhoods: { path: "/v1/admin/neighborhoods", done: "Quartier" },
} as const;

type Kind = keyof typeof KINDS;

function body(kind: Kind, form: FormData): Record<string, unknown> {
  const name = String(form.get("name") ?? "").trim();
  const active = form.get("is_active") === "on";
  if (kind === "neighborhoods") {
    return { name, city: String(form.get("city") ?? "").trim() || "Lomé", is_active: active };
  }
  const out: Record<string, unknown> = {
    name,
    position: Number(form.get("position") ?? 0) || 0,
    is_active: active,
  };
  if (kind === "categories") out.parent_id = String(form.get("parent_id") ?? "") || null;
  return out;
}

export async function saveEntry(_: ActionResult | null, form: FormData): Promise<ActionResult> {
  const kind = String(form.get("kind")) as Kind;
  const k = KINDS[kind];
  if (!k) return { ok: false, message: "Référentiel inconnu." };
  const id = String(form.get("id") ?? "");
  try {
    await api(id ? `${k.path}/${encodeURIComponent(id)}` : k.path, {
      method: id ? "PATCH" : "POST",
      body: body(kind, form),
    });
  } catch (err) {
    return failure(err);
  }
  revalidatePath("/referentials");
  return { ok: true, message: `${k.done} ${id ? "enregistré(e)" : "ajouté(e)"}.` };
}
