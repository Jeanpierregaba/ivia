"use client";

import { AlertCircle, CheckCircle2 } from "lucide-react";
import { useActionState } from "react";

import { buttonClass } from "@/components/ui";
import type { Schemas } from "@/lib/api";
import { updateSettings } from "./actions";

type Field = { name: keyof Schemas["Settings"]; label: string; unit: string; hint?: string };

const GROUPS: { title: string; fields: Field[] }[] = [
  {
    title: "Commission",
    fields: [
      {
        name: "commission_rate_bp",
        label: "Commission",
        unit: "points de base",
        hint: "1000 = 10 % du montant des produits",
      },
    ],
  },
  {
    title: "Frais de livraison",
    fields: [
      { name: "motorbike_base_fee_xof", label: "Moto : forfait", unit: "FCFA" },
      { name: "motorbike_per_km_xof", label: "Moto : prix au km", unit: "FCFA" },
      { name: "car_base_fee_xof", label: "Voiture : forfait", unit: "FCFA" },
      { name: "car_per_km_xof", label: "Voiture : prix au km", unit: "FCFA" },
      {
        name: "distance_coefficient_pct",
        label: "Coefficient de distance",
        unit: "%",
        hint: "130 = distance à vol d'oiseau × 1,3",
      },
    ],
  },
  {
    title: "Délais",
    fields: [
      { name: "payment_timeout_minutes", label: "Délai de paiement", unit: "min" },
      { name: "seller_response_timeout_minutes", label: "Réponse de la boutique", unit: "min" },
      { name: "driver_offer_timeout_seconds", label: "Réponse du livreur", unit: "s" },
    ],
  },
  {
    title: "Attribution des livreurs",
    fields: [
      { name: "assignment_max_offers", label: "Alerte après", unit: "livreurs sollicités" },
      { name: "assignment_alert_minutes", label: "Alerte après", unit: "min sans livreur" },
    ],
  },
];

export function SettingsForm({ settings }: { settings: Schemas["Settings"] }) {
  const [state, action, pending] = useActionState(updateSettings, null);
  return (
    <form action={action} className="space-y-8">
      {GROUPS.map((g) => (
        <fieldset key={g.title} className="border-b border-border pb-8 last-of-type:border-0">
          <legend className="mb-4 text-[12px] font-semibold uppercase tracking-[0.08em] text-secondary">
            {g.title}
          </legend>
          <div className="grid grid-cols-3 gap-4">
            {g.fields.map((f) => (
              <label key={f.name} className="block">
                <span className="mb-2 block text-[13px] font-semibold text-text-secondary">{f.label}</span>
                <span className="flex items-center gap-2">
                  <input
                    name={f.name}
                    type="number"
                    step={1}
                    min={0}
                    required
                    defaultValue={String(settings[f.name])}
                    className="h-12 w-full rounded-field border border-border-input bg-surface px-4 outline-none focus:border-2 focus:border-primary"
                  />
                  <span className="shrink-0 text-[13px] text-text-muted">{f.unit}</span>
                </span>
                {f.hint && <span className="mt-1 block text-[13px] text-text-muted">{f.hint}</span>}
              </label>
            ))}
          </div>
        </fieldset>
      ))}
      <label className="block">
        <span className="mb-2 block text-[13px] font-semibold text-text-secondary">
          Motif de la modification (journal)
        </span>
        <input
          name="reason"
          maxLength={300}
          placeholder="Ex. ajustement des frais de livraison"
          className="h-12 w-full rounded-field border border-border-input bg-surface px-4 outline-none focus:border-2 focus:border-primary"
        />
      </label>
      {state && (
        <p
          role="status"
          className={`flex items-center gap-2 text-[13px] ${state.ok ? "text-success" : "text-error"}`}
        >
          {state.ok ? (
            <CheckCircle2 size={16} aria-hidden="true" />
          ) : (
            <AlertCircle size={16} aria-hidden="true" />
          )}
          {state.message}
          {!state.ok &&
            state.fields &&
            Object.values(state.fields).length > 0 &&
            ` (${Object.values(state.fields).join(" ")})`}
        </p>
      )}
      <button type="submit" disabled={pending} className={buttonClass("imperial")}>
        {pending ? "Enregistrement…" : "Enregistrer les paramètres"}
      </button>
    </form>
  );
}
