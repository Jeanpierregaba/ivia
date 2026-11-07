import { ServerForm } from "@/components/server-form";
import { Field, fieldClass } from "@/components/ui";
import type { Schemas } from "@/lib/api";
import { PROPERTY_KIND, PROPERTY_TYPE } from "@/lib/format";
import { saveProperty } from "./actions";

/** Formulaire d'annonce : création, ou modification si une annonce est fournie. */
export function PropertyForm({ property: p }: { property?: Schemas["AdminProperty"] }) {
  return (
    <ServerForm
      action={saveProperty}
      submitLabel={p ? "Enregistrer" : "Publier l'annonce"}
      variant="imperial"
    >
      {p && <input type="hidden" name="id" value={p.id} />}
      <div className="grid grid-cols-4 gap-4">
        <div className="col-span-2">
          <Field label="Titre">
            <input
              name="title"
              required
              minLength={3}
              maxLength={120}
              defaultValue={p?.title}
              className={fieldClass}
            />
          </Field>
        </div>
        <Field label="Annonce">
          <select name="kind" defaultValue={p?.kind ?? "rent"} className={fieldClass}>
            {Object.entries(PROPERTY_KIND).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Type de bien">
          <select name="property_type" defaultValue={p?.property_type ?? "house"} className={fieldClass}>
            {Object.entries(PROPERTY_TYPE).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Prix (FCFA)" hint="Loyer mensuel pour une location">
          <input
            name="price_xof"
            inputMode="numeric"
            required
            defaultValue={p?.price_xof}
            className={fieldClass}
          />
        </Field>
        <Field label="Chambres">
          <input
            name="bedrooms"
            type="number"
            min={0}
            max={30}
            defaultValue={p?.bedrooms ?? 0}
            className={fieldClass}
          />
        </Field>
        <Field label="Surface (m²)">
          <input
            name="surface_m2"
            type="number"
            min={0}
            defaultValue={p?.surface_m2 ?? 0}
            className={fieldClass}
          />
        </Field>
        <Field label="Quartier">
          <input
            name="neighborhood"
            required
            maxLength={80}
            defaultValue={p?.neighborhood}
            className={fieldClass}
          />
        </Field>
        <div className="col-span-2">
          <Field label="Adresse">
            <input
              name="address_text"
              maxLength={300}
              defaultValue={p?.address_text}
              className={fieldClass}
            />
          </Field>
        </div>
        <Field label="Latitude" hint="Ex. 6,1503">
          <input name="lat" inputMode="decimal" required defaultValue={p?.lat} className={fieldClass} />
        </Field>
        <Field label="Longitude" hint="Ex. 1,2131">
          <input name="lng" inputMode="decimal" required defaultValue={p?.lng} className={fieldClass} />
        </Field>
        <div className="col-span-2">
          <Field label="Nom du contact">
            <input name="contact_name" maxLength={80} defaultValue={p?.contact_name} className={fieldClass} />
          </Field>
        </div>
        <div className="col-span-2">
          <Field label="Téléphone du contact" hint="Affiché dans l'app acheteur">
            <input
              name="contact_phone"
              inputMode="tel"
              required
              defaultValue={p?.contact_phone}
              className={fieldClass}
            />
          </Field>
        </div>
      </div>
      <Field label="Description">
        <textarea
          name="description"
          rows={4}
          maxLength={2000}
          defaultValue={p?.description}
          className="w-full rounded-field border border-border-input bg-surface px-4 py-3 text-[15px]"
        />
      </Field>
      {p && p.photo_keys.length > 0 && (
        <fieldset>
          <legend className="mb-1.5 text-[13px] font-semibold text-text-secondary">
            Photos actuelles (décochez pour retirer)
          </legend>
          <div className="flex flex-wrap gap-3">
            {p.photo_keys.map((key, i) => (
              <label key={key} className="flex items-center gap-2 rounded-card border border-border p-2">
                <input
                  type="checkbox"
                  name="keep_photo"
                  value={key}
                  defaultChecked
                  className="size-4 accent-primary"
                />
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={p.photo_urls[i]} alt="" className="size-20 rounded-card object-cover" />
              </label>
            ))}
          </div>
        </fieldset>
      )}
      <Field label="Ajouter des photos" hint="JPEG, PNG ou WebP, 5 Mo au plus ; 8 photos au total">
        <input type="file" name="new_photos" multiple accept="image/jpeg,image/png,image/webp" />
      </Field>
      <label className="flex items-center gap-3">
        <input
          type="checkbox"
          name="is_active"
          defaultChecked={p?.is_active ?? true}
          className="size-4 accent-primary"
        />
        <span className="font-semibold">Visible dans l&apos;app acheteur</span>
      </label>
    </ServerForm>
  );
}
