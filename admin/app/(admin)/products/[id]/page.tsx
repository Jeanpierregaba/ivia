import { Boxes, ImagePlus, Megaphone, Package } from "lucide-react";
import Link from "next/link";

import { ServerForm } from "@/components/server-form";
import { Card, CardTitle, ErrorState, Field, fieldClass, PageHeader, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatXOF } from "@/lib/format";
import { BADGES, localInput } from "../../promo/labels";
import { saveMarketing, saveProduct, saveStock } from "../actions";

export const metadata = { title: "Produit" };

type Props = { params: Promise<{ id: string }> };

const textareaClass =
  "w-full rounded-field border border-border-input bg-surface px-4 py-2 text-[14px] outline-none focus:border-2 focus:border-primary";

export default async function ProductPage({ params }: Props) {
  const { id } = await params;
  let p: Schemas["Product"];
  let categories: Schemas["Category"][];
  try {
    [p, categories] = await Promise.all([
      api<Schemas["Product"]>(`/v1/admin/products/${id}`),
      api<{ items: Schemas["Category"][] }>("/v1/admin/categories").then((r) => r.items),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const needsPrice = p.price_xof === 0;

  return (
    <>
      <PageHeader
        overline="Produits"
        title={p.name}
        description={
          needsPrice
            ? "Brouillon : renseignez le prix (et le stock), puis cochez « En vente »."
            : p.promo_active
              ? `En promotion : ${formatXOF(p.effective_price_xof)} au lieu de ${formatXOF(p.price_xof)}.`
              : `Prix : ${formatXOF(p.price_xof)}.`
        }
        actions={
          <div className="flex items-center gap-3">
            <StatusBadge
              label={p.status === "active" ? "En vente" : p.status === "draft" ? "Brouillon" : "Retiré"}
              tone={p.status === "active" ? "success" : p.status === "draft" ? "warning" : "muted"}
            />
            <Link href="/products" className="font-semibold text-secondary hover:underline">
              Tous les produits
            </Link>
          </div>
        }
      />

      <div className="grid grid-cols-1 lg:grid-cols-[1.25fr_1fr] gap-6">
        <Card>
          <CardTitle icon={<Package size={18} />}>Fiche produit</CardTitle>
          <ServerForm action={saveProduct} submitLabel="Enregistrer la fiche" variant="imperial">
            <input type="hidden" name="id" value={p.id} />
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              {p.images.map((img) => (
                <label
                  key={img.object_key}
                  className="relative block overflow-hidden rounded-field border border-border"
                >
                  {/* eslint-disable-next-line @next/next/no-img-element -- image servie par l'API */}
                  <img src={img.url} alt="" className="aspect-square w-full object-cover" />
                  <span className="absolute left-2 top-2 flex items-center gap-1 rounded-full bg-surface/90 px-2 py-0.5 text-[12px] font-semibold">
                    <input
                      type="checkbox"
                      name="keep_image"
                      value={img.object_key}
                      defaultChecked
                      className="accent-primary"
                    />
                    Garder
                  </span>
                </label>
              ))}
              <label className="grid aspect-square cursor-pointer place-items-center rounded-field border-2 border-dashed border-border-input text-center text-[13px] text-text-muted">
                <span className="flex flex-col items-center gap-1 px-2">
                  <ImagePlus size={24} aria-hidden="true" />
                  Ajouter des photos
                </span>
                <input
                  type="file"
                  name="new_images"
                  multiple
                  accept="image/jpeg,image/png,image/webp"
                  className="sr-only"
                />
              </label>
            </div>
            <Field label="Nom">
              <input
                name="name"
                required
                minLength={2}
                maxLength={150}
                defaultValue={p.name}
                className={fieldClass}
              />
            </Field>
            <Field label="Description">
              <textarea
                name="description"
                rows={4}
                maxLength={5000}
                defaultValue={p.description}
                className={textareaClass}
              />
            </Field>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <Field
                label="Prix (FCFA)"
                hint={needsPrice ? "À renseigner avant la mise en vente" : undefined}
              >
                <input
                  name="price_xof"
                  inputMode="numeric"
                  defaultValue={needsPrice ? "" : p.price_xof}
                  className={fieldClass}
                />
              </Field>
              <Field label="Catégorie">
                <select name="category_id" defaultValue={p.category_id} className={fieldClass}>
                  {categories.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.parent_id ? `— ${c.name}` : c.name}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Taille du colis">
                <select name="parcel_size" defaultValue={p.parcel_size} className={fieldClass}>
                  <option value="small">Petit</option>
                  <option value="medium">Moyen</option>
                  <option value="large">Grand</option>
                </select>
              </Field>
            </div>
            <label className="flex items-center gap-3 font-semibold">
              <input
                type="checkbox"
                name="is_active"
                defaultChecked={p.is_active}
                className="size-4 accent-primary"
              />
              En vente (visible des acheteurs)
            </label>
          </ServerForm>
        </Card>

        <div className="space-y-6">
          <Card>
            <CardTitle icon={<Megaphone size={18} />}>Promotion et mise en avant</CardTitle>
            <ServerForm action={saveMarketing} submitLabel="Enregistrer la promotion" variant="imperial">
              <input type="hidden" name="id" value={p.id} />
              <Field
                label="Prix promotionnel (FCFA)"
                hint="Vide : pas de promotion. Inférieur au prix normal."
              >
                <input
                  name="promo_price_xof"
                  inputMode="numeric"
                  defaultValue={p.promo_price_xof ?? ""}
                  className={fieldClass}
                />
              </Field>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <Field label="Début" hint="Vide : tout de suite">
                  <input
                    name="promo_starts_at"
                    type="datetime-local"
                    defaultValue={localInput(p.promo_starts_at)}
                    className={fieldClass}
                  />
                </Field>
                <Field label="Fin" hint="Vide : sans fin">
                  <input
                    name="promo_ends_at"
                    type="datetime-local"
                    defaultValue={localInput(p.promo_ends_at)}
                    className={fieldClass}
                  />
                </Field>
              </div>
              <fieldset>
                <legend className="mb-2 text-[13px] font-semibold text-text-secondary">Badges</legend>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                  {Object.entries(BADGES).map(([value, label]) => (
                    <label
                      key={value}
                      className="flex items-center gap-2 rounded-field border border-border px-3 py-2 text-[14px]"
                    >
                      <input
                        type="checkbox"
                        name="badges"
                        value={value}
                        defaultChecked={p.badges.includes(value as never)}
                        className="size-4 accent-primary"
                      />
                      {label}
                    </label>
                  ))}
                </div>
              </fieldset>
              <Field
                label="Rang de mise en avant"
                hint="1 = toujours en tête des listes ; vide : pas de mise en avant"
              >
                <input
                  name="featured_rank"
                  type="number"
                  min={1}
                  max={1000}
                  defaultValue={p.featured_rank ?? ""}
                  className={fieldClass}
                />
              </Field>
              <Field
                label="Caractéristiques"
                hint="Une par ligne, 12 au plus (affichées sur la fiche et la publicité)"
              >
                <textarea
                  name="features"
                  rows={5}
                  defaultValue={p.features.join("\n")}
                  className={textareaClass}
                />
              </Field>
            </ServerForm>
          </Card>

          <Card>
            <CardTitle icon={<Boxes size={18} />}>Stock</CardTitle>
            {p.stock_mode === "tracked" ? (
              <ServerForm action={saveStock} submitLabel="Mettre à jour" inline>
                <input type="hidden" name="id" value={p.id} />
                <Field label="Quantité disponible">
                  <input
                    name="quantity"
                    type="number"
                    min={0}
                    required
                    defaultValue={p.stock_quantity ?? 0}
                    className={fieldClass}
                  />
                </Field>
                <Field label="Note (journal)">
                  <input name="note" maxLength={200} placeholder="Ex. arrivage" className={fieldClass} />
                </Field>
              </ServerForm>
            ) : (
              <p className="text-text-secondary">Stock non suivi : le produit est toujours disponible.</p>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}
