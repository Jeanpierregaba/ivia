import { AlertTriangle, CalendarClock, ChevronLeft, FileText, Gavel, Store, Wallet } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ActionForm } from "@/components/action-form";
import { ServerForm } from "@/components/server-form";
import { Avatar, Card, CardTitle, DefinitionList, ErrorState, Field, fieldClass, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import {
  formatDateTime,
  formatPhone,
  formatXOF,
  PHARMACY_DOCUMENT,
  PHARMACY_STATUS,
  statusOf,
} from "@/lib/format";
import { addDutyShift, deleteDutyShift, recordPayout, reviewPharmacy } from "../actions";

export const metadata = { title: "Dossier pharmacie" };

export default async function PharmacyPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const path = `/v1/admin/pharmacies/${encodeURIComponent(id)}`;
  let p: Schemas["AdminPharmacy"];
  let earnings: Schemas["PharmacyEarnings"];
  let shifts: Schemas["PharmacyDutyShift"][];
  try {
    const [a, b, c] = await Promise.all([
      api<Schemas["AdminPharmacy"]>(path),
      api<Schemas["PharmacyEarnings"]>(`${path}/earnings`),
      api<{ items: Schemas["PharmacyDutyShift"][] }>(`${path}/duty-shifts`),
    ]);
    p = a;
    earnings = b;
    shifts = c.items;
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const hidden = (decision: string) => ({ id: p.id, decision });
  const missing = p.missing_documents.map((k) => PHARMACY_DOCUMENT[k] ?? k);

  return (
    <>
      <Link
        href="/pharmacies"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Pharmacies
      </Link>
      <header className="mb-6 flex items-center gap-5 rounded-field bg-tertiary p-6 text-white">
        <Avatar name={p.name || "?"} tone="cobalt" size={64} />
        <div className="min-w-0 flex-1">
          <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-white/60">Dossier pharmacie</p>
          <h1 className="text-[28px] font-bold leading-8 tracking-[-0.02em]">{p.name}</h1>
          <p className="mt-1 text-white/75">
            {p.address_text} · {formatPhone(p.phone)}
          </p>
        </div>
        <span className="rounded-full bg-surface">
          <StatusBadge {...statusOf(PHARMACY_STATUS, p.status)} />
        </span>
      </header>

      <div className="grid grid-cols-2 gap-4">
        <Card>
          <CardTitle icon={<Store size={18} aria-hidden="true" />}>Officine</CardTitle>
          <DefinitionList
            items={[
              ["Titulaire", `${p.owner_first_name || "—"} · ${formatPhone(p.owner_phone)}`],
              ["N° d'autorisation", p.license_number || "—"],
              ["Horaires", p.opening_hours || "—"],
              ["État", [p.is_open && "Ouverte", p.on_duty && "De garde", p.open_24h && "24 h/24"].filter(Boolean).join(" · ") || "Fermée"],
              ["Position", `${p.location.lat.toFixed(5)}, ${p.location.lng.toFixed(5)}`],
              ["Inscription", formatDateTime(p.created_at)],
              ["Dernière décision", formatDateTime(p.reviewed_at)],
              ["Note", p.review_note || p.suspension_reason || "—"],
            ]}
          />
        </Card>

        <Card>
          <CardTitle icon={<FileText size={18} aria-hidden="true" />}>Pièces</CardTitle>
          {p.documents.length === 0 ? (
            <p className="text-text-secondary">Aucune pièce déposée.</p>
          ) : (
            <ul className="space-y-2">
              {p.documents.map((doc) => (
                <li
                  key={doc.id}
                  className="flex items-center justify-between rounded-card bg-background px-4 py-3"
                >
                  <span className="flex items-center gap-2 font-semibold">
                    <FileText size={16} aria-hidden="true" className="text-secondary" />
                    {PHARMACY_DOCUMENT[doc.kind] ?? doc.kind}
                  </span>
                  {doc.url ? (
                    // Lien temporaire (10 min) vers le compartiment privé.
                    <a href={doc.url} target="_blank" rel="noreferrer" className="font-semibold text-secondary hover:underline">
                      Consulter
                    </a>
                  ) : (
                    <span className="text-text-muted">indisponible</span>
                  )}
                </li>
              ))}
            </ul>
          )}
          {missing.length > 0 && (
            <p
              role="status"
              className="mt-4 flex items-start gap-2 rounded-card bg-[#FBEFE3] px-4 py-3 text-[13px] text-warning"
            >
              <AlertTriangle size={16} aria-hidden="true" className="mt-px shrink-0" />
              Manquant : {missing.join(", ")}.
            </p>
          )}
        </Card>
      </div>

      <Card className="mt-4">
        <CardTitle icon={<Gavel size={18} aria-hidden="true" />}>Décision</CardTitle>
        <div className="flex flex-wrap gap-2">
          {(p.review_status === "pending_review" || p.review_status === "rejected") && (
            <ActionForm
              action={reviewPharmacy}
              label="Valider la pharmacie"
              hidden={hidden("approve")}
              confirm={{
                title: `Valider ${p.name} ?`,
                body: "Après vérification des pièces, la pharmacie pourra recevoir les alertes des patients.",
              }}
            />
          )}
          {p.review_status === "pending_review" && (
            <ActionForm
              action={reviewPharmacy}
              label="Refuser"
              variant="outline"
              hidden={hidden("reject")}
              confirm={{
                title: `Refuser le dossier de ${p.name} ?`,
                body: "Le motif est communiqué au titulaire, qui peut corriger son dossier.",
              }}
              reason={{ label: "Motif du refus", required: true }}
            />
          )}
          {p.review_status === "approved" && !p.suspended_at && (
            <ActionForm
              action={reviewPharmacy}
              label="Suspendre"
              variant="danger"
              hidden={hidden("suspend")}
              confirm={{
                title: `Suspendre ${p.name} ?`,
                body: "La pharmacie cesse immédiatement de recevoir des alertes.",
              }}
              reason={{ label: "Motif de la suspension", required: true }}
            />
          )}
          {p.suspended_at && (
            <ActionForm
              action={reviewPharmacy}
              label="Rétablir"
              variant="outline"
              hidden={hidden("reinstate")}
              confirm={{ title: `Rétablir ${p.name} ?`, body: "La pharmacie pourra de nouveau recevoir des alertes." }}
            />
          )}
        </div>
      </Card>

      <div className="mt-4 grid grid-cols-2 gap-4">
        <Card>
          <CardTitle icon={<CalendarClock size={18} aria-hidden="true" />}>Planning de garde</CardTitle>
          {shifts.length === 0 ? (
            <p className="mb-4 text-text-secondary">Aucune garde planifiée.</p>
          ) : (
            <ul className="mb-4 space-y-2">
              {shifts.map((s) => (
                <li key={s.id} className="rounded-card bg-background px-4 py-3">
                  <p className="font-semibold">
                    {formatDateTime(s.starts_at)} → {formatDateTime(s.ends_at)}
                  </p>
                  <ActionForm
                    action={deleteDutyShift}
                    label="Retirer"
                    variant="outline"
                    hidden={{ id: s.id, pharmacy_id: p.id }}
                    confirm={{ title: "Retirer cette garde ?", body: "La garde disparaît du planning de la pharmacie." }}
                    reason={{ label: "Motif" }}
                  />
                </li>
              ))}
            </ul>
          )}
          <ServerForm action={addDutyShift} submitLabel="Ajouter la garde" variant="outline">
            <input type="hidden" name="id" value={p.id} />
            <div className="grid grid-cols-2 gap-3">
              <Field label="Début (heure de Lomé)">
                <input type="datetime-local" name="starts_at" required className={fieldClass} />
              </Field>
              <Field label="Fin (heure de Lomé)">
                <input type="datetime-local" name="ends_at" required className={fieldClass} />
              </Field>
            </div>
          </ServerForm>
        </Card>

        <Card>
          <CardTitle icon={<Wallet size={18} aria-hidden="true" />}>Solde et reversements</CardTitle>
          <DefinitionList
            items={[
              ["À reverser", formatXOF(earnings.balance_xof)],
              ["Déjà reversé", formatXOF(earnings.paid_out_xof)],
              ["Ventes livrées", String(earnings.delivered_count)],
              ["Retraits sur place", String(earnings.pickup_count)],
            ]}
          />
          {earnings.payouts.length > 0 && (
            <ul className="mt-4 space-y-2">
              {earnings.payouts.map((v) => (
                <li key={v.id} className="flex justify-between rounded-card bg-background px-4 py-3">
                  <span>
                    {formatDateTime(v.created_at)} · {v.reference}
                  </span>
                  <span className="font-semibold">{formatXOF(v.amount_xof)}</span>
                </li>
              ))}
            </ul>
          )}
          <ServerForm action={recordPayout} submitLabel="Enregistrer le reversement" variant="outline" className="mt-4">
            <input type="hidden" name="id" value={p.id} />
            <div className="grid grid-cols-2 gap-3">
              <Field label="Montant (FCFA)">
                <input name="amount_xof" inputMode="numeric" required className={fieldClass} />
              </Field>
              <Field label="Référence du virement">
                <input name="reference" required maxLength={100} className={fieldClass} />
              </Field>
            </div>
            <Field label="Note (facultatif)">
              <input name="note" maxLength={300} className={fieldClass} />
            </Field>
          </ServerForm>
        </Card>
      </div>
    </>
  );
}
