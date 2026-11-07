import { ServerForm } from "@/components/server-form";
import { Card, ErrorState, Field, fieldClass, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, VTC_MODE } from "@/lib/format";
import { saveDriverSettings } from "../drivers/actions";

export const metadata = { title: "Réglages partenaires" };

const MODE_HINT: Record<string, string> = {
  hidden: "Le taxi VTC n'apparaît pas dans l'app livreur.",
  preregistration: "Les chauffeurs déposent leur dossier ; les courses restent fermées.",
  open: "Inscriptions ouvertes (les courses VTC ne sont pas encore développées).",
};

export default async function DriverSettingsPage() {
  let s: Schemas["DriverSettings"];
  try {
    s = await api<Schemas["DriverSettings"]>("/v1/admin/driver-settings");
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Flotte"
        title="Les réglages des partenaires"
        highlight="partenaires"
        description={`Livreurs et chauffeurs. Chaque modification est journalisée. Dernière modification : ${formatDateTime(s.updated_at)}.`}
      />
      <Card>
        <ServerForm action={saveDriverSettings} submitLabel="Enregistrer les réglages">
          <fieldset className="grid grid-cols-3 gap-4">
            <legend className="mb-2 font-semibold">Taxi VTC</legend>
            {Object.entries(VTC_MODE).map(([value, label]) => (
              <label key={value} className="flex items-start gap-3 rounded-field border border-border p-4">
                <input
                  type="radio"
                  name="vtc_mode"
                  value={value}
                  defaultChecked={s.vtc_mode === value}
                  className="mt-1 size-4 accent-secondary"
                />
                <span>
                  <span className="block font-semibold">{label}</span>
                  <span className="text-[12px] text-text-muted">{MODE_HINT[value]}</span>
                </span>
              </label>
            ))}
          </fieldset>
          <label className="flex items-start gap-3 rounded-field border border-border p-4">
            <input
              type="checkbox"
              name="delivery_vehicle_check"
              defaultChecked={s.delivery_vehicle_check}
              className="mt-1 size-4 accent-secondary"
            />
            <span>
              <span className="block font-semibold">Contrôle du véhicule sur place pour la livraison</span>
              <span className="text-[12px] text-text-muted">
                Toujours exigé pour le taxi VTC. Coché : aussi exigé avant de valider un livreur.
              </span>
            </span>
          </label>
          <Field label="Guide du partenaire" hint="Affiché dans l'app livreur pendant la vérification du dossier.">
            <textarea
              name="partner_guide"
              rows={10}
              maxLength={20000}
              defaultValue={s.partner_guide}
              className={fieldClass}
            />
          </Field>
        </ServerForm>
      </Card>
    </>
  );
}
