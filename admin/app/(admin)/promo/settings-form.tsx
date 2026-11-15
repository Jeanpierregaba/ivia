"use client";

import { ServerForm } from "@/components/server-form";
import { Field, fieldClass } from "@/components/ui";
import type { Schemas } from "@/lib/api";
import { saveSettings } from "./actions";
import { ROTATIONS } from "./labels";

const SWITCHES = [
  { name: "enabled", label: "Publicité activée", hint: "Coupe tout d'un coup si décoché" },
  { name: "banners_enabled", label: "Bannières et produits mis en avant" },
  { name: "modal_enabled", label: "Fenêtres pendant la navigation" },
  { name: "interstitial_enabled", label: "Interstitiels plein écran" },
] as const;

export function PromoSettingsForm({ settings }: { settings: Schemas["PromoSettings"] }) {
  return (
    <ServerForm action={saveSettings} submitLabel="Enregistrer les réglages" variant="imperial">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {SWITCHES.map((s) => (
          <label key={s.name} className="flex items-start gap-3 rounded-field border border-border p-4">
            <input
              type="checkbox"
              name={s.name}
              defaultChecked={settings[s.name]}
              className="mt-1 size-4 accent-primary"
            />
            <span>
              <span className="block font-semibold">{s.label}</span>
              {"hint" in s && <span className="text-[12px] text-text-muted">{s.hint}</span>}
            </span>
          </label>
        ))}
      </div>
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <Field label="Première fenêtre après (s)" hint="Délai après l'ouverture de l'app">
          <input
            name="first_delay_seconds"
            type="number"
            min={0}
            max={600}
            defaultValue={settings.first_delay_seconds}
            className={fieldClass}
          />
        </Field>
        <Field label="Intervalle minimal (s)" hint="Entre deux fenêtres ou interstitiels">
          <input
            name="min_interval_seconds"
            type="number"
            min={15}
            max={3600}
            defaultValue={settings.min_interval_seconds}
            className={fieldClass}
          />
        </Field>
        <Field label="Maximum par session" hint="Fenêtres et interstitiels ; 0 = aucun">
          <input
            name="max_per_session"
            type="number"
            min={0}
            max={50}
            defaultValue={settings.max_per_session}
            className={fieldClass}
          />
        </Field>
        <Field label="Produit vedette toutes les … cartes" hint="Réapparition dans les listes">
          <input
            name="feed_every"
            type="number"
            min={3}
            max={50}
            defaultValue={settings.feed_every}
            className={fieldClass}
          />
        </Field>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Field label="Rotation des visuels">
          <select name="rotation" defaultValue={settings.rotation} className={fieldClass}>
            {Object.entries(ROTATIONS).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Site officiel IVI" hint="Bouton « Visiter le site officiel » (https://)">
          <input name="official_url" type="url" defaultValue={settings.official_url} className={fieldClass} />
        </Field>
      </div>
    </ServerForm>
  );
}
