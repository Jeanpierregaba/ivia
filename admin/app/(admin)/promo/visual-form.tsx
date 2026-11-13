"use client";

import { ImagePlus } from "lucide-react";
import { useState } from "react";

import { ServerForm } from "@/components/server-form";
import { Field, fieldClass } from "@/components/ui";
import type { Schemas } from "@/lib/api";
import { saveVisual } from "./actions";
import { APPS, KINDS, localInput, PLACEMENTS } from "./labels";

type Props = {
  visual?: Schemas["PromoVisual"];
  products: { id: string; name: string }[];
  officialURL: string;
};

/** Création ou modification d'un visuel, avec aperçu de l'image choisie. */
export function VisualForm({ visual, products, officialURL }: Props) {
  const [preview, setPreview] = useState<string | null>(visual?.image_url ?? null);
  const [kind, setKind] = useState<string>(visual?.kind ?? "modal");
  const v = visual;

  return (
    <ServerForm action={saveVisual} submitLabel={v ? "Enregistrer" : "Publier le visuel"} variant="imperial">
      {v && <input type="hidden" name="id" value={v.id} />}
      {v && <input type="hidden" name="image_key" value={v.image_key} />}
      <div className="grid grid-cols-1 lg:grid-cols-[1.1fr_1fr] gap-8">
        <div className="space-y-4">
          <label className="group relative grid aspect-[16/9] cursor-pointer place-items-center overflow-hidden rounded-field border-2 border-dashed border-border-input bg-background-alt">
            {preview ? (
              // eslint-disable-next-line @next/next/no-img-element -- aperçu local ou image de l'API
              <img src={preview} alt="Aperçu du visuel" className="absolute inset-0 size-full object-cover" />
            ) : (
              <span className="flex flex-col items-center gap-2 text-text-muted">
                <ImagePlus size={32} aria-hidden="true" />
                Choisir l&apos;image (JPEG, PNG ou WebP, 5 Mo au plus)
              </span>
            )}
            <input
              type="file"
              name="image"
              accept="image/jpeg,image/png,image/webp"
              className="sr-only"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) setPreview(URL.createObjectURL(f));
              }}
            />
            {preview && (
              <span className="absolute bottom-3 right-3 rounded-full bg-tertiary/85 px-3 py-1 text-[13px] font-semibold text-white opacity-0 transition-opacity group-hover:opacity-100">
                Changer l&apos;image
              </span>
            )}
          </label>
          <p className="text-[13px] text-text-muted">
            Conseil : 1600 × 900 pour les bannières, 900 × 1200 (portrait) pour les fenêtres et interstitiels.
          </p>
          <fieldset>
            <legend className="mb-2 text-[13px] font-semibold text-text-secondary">
              Emplacements dans les apps
            </legend>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
              {Object.entries(PLACEMENTS).map(([value, label]) => (
                <label
                  key={value}
                  className="flex items-center gap-2 rounded-field border border-border px-3 py-2 text-[14px]"
                >
                  <input
                    type="checkbox"
                    name="placements"
                    value={value}
                    defaultChecked={v ? v.placements.includes(value as never) : value === "modal"}
                    className="size-4 accent-primary"
                  />
                  {label}
                </label>
              ))}
            </div>
          </fieldset>
          <fieldset>
            <legend className="mb-2 text-[13px] font-semibold text-text-secondary">Apps</legend>
            <div className="flex gap-2">
              {Object.entries(APPS).map(([value, label]) => (
                <label
                  key={value}
                  className="flex items-center gap-2 rounded-field border border-border px-3 py-2 text-[14px]"
                >
                  <input
                    type="checkbox"
                    name="apps"
                    value={value}
                    defaultChecked={v ? v.apps.includes(value as never) : value === "buyer"}
                    className="size-4 accent-primary"
                  />
                  {label}
                </label>
              ))}
            </div>
          </fieldset>
        </div>

        <div className="space-y-4">
          <Field label="Type de visuel" hint={KINDS[kind]?.hint}>
            <select name="kind" value={kind} onChange={(e) => setKind(e.target.value)} className={fieldClass}>
              {Object.entries(KINDS).map(([value, k]) => (
                <option key={value} value={value}>
                  {k.label}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Titre">
            <input
              name="title"
              required
              minLength={2}
              maxLength={80}
              defaultValue={v?.title}
              className={fieldClass}
            />
          </Field>
          <Field label="Sous-titre">
            <input name="subtitle" maxLength={140} defaultValue={v?.subtitle} className={fieldClass} />
          </Field>
          <Field label="Texte (argumentaire)">
            <textarea
              name="body"
              rows={3}
              maxLength={600}
              defaultValue={v?.body}
              className="w-full rounded-field border border-border-input bg-surface px-4 py-2 text-[15px] outline-none focus:border-2 focus:border-primary"
            />
          </Field>
          <Field
            label="Produit à commander"
            hint="Bouton « Commander maintenant » (produit en vente uniquement)"
          >
            <select name="product_id" defaultValue={v?.product_id ?? ""} className={fieldClass}>
              <option value="">Aucun</option>
              {products.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </Field>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Field label="Texte du bouton">
              <input
                name="cta_label"
                maxLength={30}
                defaultValue={v?.cta_label ?? "Commander maintenant"}
                className={fieldClass}
              />
            </Field>
            <Field label="Lien externe" hint="Site officiel (https://)">
              <input
                name="external_url"
                type="url"
                defaultValue={v?.external_url ?? officialURL}
                className={fieldClass}
              />
            </Field>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Field label="Priorité (0 à 100)" hint="Les plus hautes passent d'abord">
              <input
                name="priority"
                type="number"
                min={0}
                max={100}
                defaultValue={v?.priority ?? 50}
                className={fieldClass}
              />
            </Field>
            <Field label="Poids (1 à 100)" hint="Fréquence en rotation pondérée">
              <input
                name="weight"
                type="number"
                min={1}
                max={100}
                defaultValue={v?.weight ?? 3}
                className={fieldClass}
              />
            </Field>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Field label="Début (heure de Lomé)" hint="Vide : tout de suite">
              <input
                name="starts_at"
                type="datetime-local"
                defaultValue={localInput(v?.starts_at)}
                className={fieldClass}
              />
            </Field>
            <Field label="Fin (heure de Lomé)" hint="Vide : sans fin">
              <input
                name="ends_at"
                type="datetime-local"
                defaultValue={localInput(v?.ends_at)}
                className={fieldClass}
              />
            </Field>
          </div>
          <label className="flex items-center gap-3 font-semibold">
            <input
              type="checkbox"
              name="is_active"
              defaultChecked={v?.is_active ?? true}
              className="size-4 accent-primary"
            />
            Diffuser ce visuel
          </label>
        </div>
      </div>
    </ServerForm>
  );
}
