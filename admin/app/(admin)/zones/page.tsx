import { Hexagon } from "lucide-react";

import { ActionForm } from "@/components/action-form";
import { ServerForm } from "@/components/server-form";
import { Card, CardTitle, EmptyState, ErrorState, Field, fieldClass, PageHeader, StatusBadge, Table, Td } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { deleteZone, saveZone } from "../places/actions";

export const metadata = { title: "Zones" };

const TYPES: Record<string, string> = {
  service_area: "Zone desservie",
  pricing: "Tarif",
  surge: "Majoration",
  airport: "Aéroport",
};

export default async function ZonesPage() {
  let zones: Schemas["GeoZone"][];
  try {
    zones = (await api<{ items: Schemas["GeoZone"][] }>("/v1/admin/zones")).items;
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Carte"
        title="Les zones desservies et leurs tarifs"
        highlight="zones"
        description="Sans tarif sur le point de départ, aucune estimation de prix n'est donnée : aucun prix n'est écrit dans le code."
      />
      <Card className="mb-4">
        <CardTitle icon={<Hexagon size={18} aria-hidden="true" />}>Ajouter une zone</CardTitle>
        <ServerForm action={saveZone} submitLabel="Ajouter" variant="imperial">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Nom">
              <input name="name" required maxLength={120} className={fieldClass} />
            </Field>
            <Field label="Type">
              <select name="type" className={fieldClass} defaultValue="pricing">
                {Object.entries(TYPES).map(([v, l]) => (
                  <option key={v} value={v}>
                    {l}
                  </option>
                ))}
              </select>
            </Field>
          </div>
          <div className="grid grid-cols-4 gap-3">
            <Field label="Prise en charge (FCFA)">
              <input name="base_xof" type="number" min={0} className={fieldClass} />
            </Field>
            <Field label="Par km (FCFA)">
              <input name="per_km_xof" type="number" min={0} className={fieldClass} />
            </Field>
            <Field label="Par minute (FCFA)">
              <input name="per_min_xof" type="number" min={0} className={fieldClass} />
            </Field>
            <Field label="Multiplicateur" hint="Majoration : 1,5 par exemple">
              <input name="multiplier" type="number" step="0.1" min={0} max={10} className={fieldClass} />
            </Field>
          </div>
          <Field label="Polygone GeoJSON" hint="Se dessine sur geojson.io, puis se colle ici (géométrie Polygon)">
            <textarea
              name="geojson"
              required
              rows={4}
              className="w-full rounded-field border border-border-input bg-surface px-4 py-3 font-mono text-[13px]"
              placeholder='{"type":"Polygon","coordinates":[[[1.15,6.10],[1.30,6.10],[1.30,6.25],[1.15,6.25],[1.15,6.10]]]}'
            />
          </Field>
          <label className="flex items-center gap-3">
            <input type="checkbox" name="is_active" defaultChecked className="size-4 accent-primary" />
            <span className="font-semibold">Active</span>
          </label>
        </ServerForm>
      </Card>
      {zones.length === 0 ? (
        <EmptyState title="Aucune zone" message="Ajoutez une zone de tarif pour activer les estimations de prix." />
      ) : (
        <Table head={["Zone", "Type", "Tarif", "État", ""]}>
          {zones.map((z) => (
            <tr key={z.id}>
              <Td>
                <span className="font-semibold">{z.name}</span>
              </Td>
              <Td>{TYPES[z.type] ?? z.type}</Td>
              <Td>
                {z.type === "surge"
                  ? `× ${z.rules?.multiplier ?? 1}`
                  : z.type === "service_area"
                    ? "—"
                    : `${z.rules?.base_xof ?? 0} F + ${z.rules?.per_km_xof ?? 0} F/km + ${z.rules?.per_min_xof ?? 0} F/min`}
              </Td>
              <Td>
                <StatusBadge label={z.is_active ? "Active" : "Inactive"} tone={z.is_active ? "success" : "muted"} />
              </Td>
              <Td>
                <ActionForm
                  action={deleteZone}
                  label="Retirer"
                  variant="outline"
                  hidden={{ id: z.id }}
                  confirm={{ title: `Retirer la zone ${z.name} ?`, body: "Les estimations de prix ne l'utiliseront plus." }}
                />
              </Td>
            </tr>
          ))}
        </Table>
      )}
    </>
  );
}
