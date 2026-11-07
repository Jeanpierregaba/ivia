import { ServerForm } from "@/components/server-form";
import { Card, ErrorState, Field, fieldClass, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { savePharmacySettings } from "../pharmacies/actions";

export const metadata = { title: "Réglages santé" };

export default async function PharmacySettingsPage() {
  let s: Schemas["PharmacySettings"];
  try {
    s = await api<Schemas["PharmacySettings"]>("/v1/admin/pharmacy/settings");
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const num = (name: keyof Schemas["PharmacySettings"], label: string, hint?: string) => (
    <Field label={label} hint={hint}>
      <input
        name={name}
        type="number"
        min={0}
        required
        defaultValue={Number(s[name])}
        className={fieldClass}
      />
    </Field>
  );

  return (
    <>
      <PageHeader
        overline="Santé"
        title="Les réglages de l'alerte médicament"
        highlight="réglages"
        description="Prix, rayons et délais. Chaque modification est journalisée."
      />
      <Card>
        <ServerForm action={savePharmacySettings} submitLabel="Enregistrer les réglages" variant="imperial">
          <div className="grid grid-cols-2 gap-4">
            <label className="flex items-start gap-3 rounded-field border border-border p-4">
              <input
                type="checkbox"
                name="enabled"
                defaultChecked={s.enabled}
                className="mt-1 size-4 accent-primary"
              />
              <span>
                <span className="block font-semibold">Alerte médicament activée</span>
                <span className="text-[12px] text-text-muted">
                  Coupe le service d&apos;un coup si décoché
                </span>
              </span>
            </label>
            <label className="flex items-start gap-3 rounded-field border border-border p-4">
              <input
                type="checkbox"
                name="auto_widen"
                defaultChecked={s.auto_widen}
                className="mt-1 size-4 accent-primary"
              />
              <span>
                <span className="block font-semibold">Élargir le rayon automatiquement</span>
                <span className="text-[12px] text-text-muted">Quand il y a trop peu de réponses</span>
              </span>
            </label>
          </div>
          <div className="grid grid-cols-4 gap-4">
            {num("unlock_fee_xof", "Forfait de déblocage (FCFA)", "Par pharmacie débloquée")}
            {num("product_commission_bp", "Commission produits (points de base)", "100 = 1 %")}
            {num("search_radius_m", "Rayon par défaut (m)")}
            {num("max_radius_m", "Rayon maximal (m)")}
            <Field label="Rayons proposés (m)" hint="Séparés par des virgules">
              <input
                name="radius_options_m"
                required
                defaultValue={s.radius_options_m.join(", ")}
                className={fieldClass}
              />
            </Field>
            {num("target_responses", "Réponses visées")}
            {num("widen_after_minutes", "Élargir après (min)")}
            {num("response_window_minutes", "Délai de réponse (min)")}
            {num("pickup_hold_minutes", "Mise de côté (min)")}
            {num("photo_retention_hours", "Conservation des photos (h)")}
            {num(
              "night_from_hour",
              "Début de la nuit par défaut",
              "Chaque pharmacie peut choisir ses heures",
            )}
            {num("night_to_hour", "Fin de la nuit par défaut", "Égale au début : pas de restriction")}
          </div>
          <Field label="Motif du changement">
            <input name="reason" maxLength={500} className={fieldClass} />
          </Field>
        </ServerForm>
      </Card>
    </>
  );
}
