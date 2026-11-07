import { AlertTriangle, Car, CheckCircle2, ChevronLeft, FileText, Gavel, IdCard, Wallet } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ActionForm } from "@/components/action-form";
import { Avatar, Card, CardTitle, DefinitionList, ErrorState, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import {
  DOCUMENT_KIND,
  DRIVER_ACTIVITY,
  DRIVER_STATUS,
  formatDateTime,
  formatPhone,
  statusOf,
  VEHICLE,
} from "@/lib/format";
import { checkVehicle, reviewActivity, reviewDriver } from "../actions";

export const metadata = { title: "Dossier partenaire" };

const OPERATOR: Record<string, string> = { flooz: "Moov Money (Flooz)", tmoney: "Yas (T-Money)" };

type Activity = Schemas["DriverActivity"];

export default async function DriverPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  let d: Schemas["AdminDriver"];
  try {
    d = await api<Schemas["AdminDriver"]>(`/v1/admin/drivers/${encodeURIComponent(id)}`);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  // Noms des zones de travail ; sans eux, l'identifiant suffit.
  let zones: Schemas["GeoZone"][] = [];
  try {
    zones = (await api<{ items: Schemas["GeoZone"][] }>("/v1/admin/zones")).items;
  } catch {
    zones = [];
  }

  const activities = d.activities ?? [];
  const name = d.first_name || "ce partenaire";
  const hidden = (decision: string) => ({ id: d.user_id, decision });

  return (
    <>
      <Link
        href="/drivers"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Livreurs et chauffeurs
      </Link>
      <header className="mb-6 flex items-center gap-5 rounded-field bg-tertiary p-6 text-white">
        <Avatar name={d.first_name || "?"} tone="cobalt" size={64} />
        <div className="min-w-0 flex-1">
          <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-white/60">
            Dossier partenaire
          </p>
          <h1 className="text-[28px] font-bold leading-8 tracking-[-0.02em]">
            {d.first_name || "Sans prénom"}
          </h1>
          <p className="mt-1 text-white/75">
            {activities.map((a) => DRIVER_ACTIVITY[a.activity] ?? a.activity).join(" · ") ||
              "Aucune activité"}
            {" · "}
            {formatPhone(d.phone)}
          </p>
        </div>
        <span className="rounded-full bg-surface">
          <StatusBadge {...statusOf(DRIVER_STATUS, d.status)} />
        </span>
      </header>

      <div className="grid grid-cols-2 gap-4">
        <Card>
          <CardTitle icon={<IdCard size={18} aria-hidden="true" />}>Identité</CardTitle>
          <DefinitionList
            items={[
              ["Prénom", d.first_name || "—"],
              ["Téléphone", formatPhone(d.phone)],
              ["Inscription", formatDateTime(d.created_at)],
              [
                "Suspension",
                d.suspended_at ? `${formatDateTime(d.suspended_at)} · ${d.suspension_reason}` : "—",
              ],
            ]}
          />
        </Card>
        <Card>
          <CardTitle icon={<Wallet size={18} aria-hidden="true" />}>Compte de versement</CardTitle>
          {d.payout ? (
            <DefinitionList
              items={[
                ["Opérateur", OPERATOR[d.payout.operator] ?? d.payout.operator],
                ["Numéro", formatPhone(d.payout.phone || d.payout.phone_masked)],
                ["Titulaire", d.payout.holder],
              ]}
            />
          ) : (
            <p className="text-text-secondary">Pas encore renseigné.</p>
          )}
        </Card>
      </div>

      {activities.map((a) => (
        <ActivityCard key={a.activity} driver={d} activity={a} zones={zones} name={name} />
      ))}

      <Card className="mt-4">
        <CardTitle icon={<FileText size={18} aria-hidden="true" />}>Documents déposés</CardTitle>
        {d.documents.length === 0 ? (
          <p className="text-text-secondary">Aucun document déposé.</p>
        ) : (
          <ul className="grid grid-cols-2 gap-2">
            {d.documents.map((doc) => (
              <li
                key={doc.id}
                className="flex items-center justify-between rounded-card bg-background px-4 py-3"
              >
                <span className="flex items-center gap-2 font-semibold">
                  <FileText size={16} aria-hidden="true" className="text-secondary" />
                  {DOCUMENT_KIND[doc.kind] ?? doc.kind}
                </span>
                {doc.url ? (
                  // Lien temporaire (10 min) vers le compartiment privé.
                  <a
                    href={doc.url}
                    target="_blank"
                    rel="noreferrer"
                    className="font-semibold text-secondary hover:underline"
                  >
                    Consulter
                  </a>
                ) : (
                  <span className="text-text-muted">indisponible</span>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>

      {(d.review_status === "approved" || d.suspended_at) && (
        <Card className="mt-4">
          <CardTitle icon={<Gavel size={18} aria-hidden="true" />}>Compte</CardTitle>
          <div className="flex flex-wrap gap-2">
            {d.review_status === "approved" && !d.suspended_at && (
              <ActionForm
                action={reviewDriver}
                label="Suspendre"
                variant="danger"
                hidden={hidden("suspend")}
                confirm={{
                  title: `Suspendre ${name} ?`,
                  body: "Le livreur perd l'accès aux missions immédiatement ; une mission non commencée repart à l'attribution.",
                }}
                reason={{ label: "Motif de la suspension", required: true }}
              />
            )}
            {d.suspended_at && (
              <ActionForm
                action={reviewDriver}
                label="Rétablir"
                variant="outline"
                hidden={hidden("reinstate")}
                confirm={{
                  title: `Rétablir ${name} ?`,
                  body: "Le livreur pourra de nouveau passer en ligne.",
                }}
              />
            )}
          </div>
        </Card>
      )}
    </>
  );
}

function ActivityCard({
  driver,
  activity: a,
  zones,
  name,
}: {
  driver: Schemas["AdminDriver"];
  activity: Activity;
  zones: Schemas["GeoZone"][];
  name: string;
}) {
  const label = DRIVER_ACTIVITY[a.activity] ?? a.activity;
  const v = a.vehicle;
  const zone = a.work_zone_id ? (zones.find((z) => z.id === a.work_zone_id)?.name ?? a.work_zone_id) : "—";
  const base = { id: driver.user_id, activity: a.activity };
  const missing = a.missing_documents ?? [];
  const pending = a.status === "pending_review";
  const check = a.vehicle_check;

  return (
    <Card className="mt-4">
      <CardTitle
        icon={<Car size={18} aria-hidden="true" />}
        aside={<StatusBadge {...statusOf(DRIVER_STATUS, a.status)} />}
      >
        {label}
      </CardTitle>
      <div className="grid grid-cols-2 gap-6">
        <DefinitionList
          items={[
            ["Véhicule", [VEHICLE[v.type] ?? v.type, v.brand, v.model, v.color].filter(Boolean).join(" · ")],
            ["Immatriculation", v.plate || "—"],
            ...(a.activity === "vtc" ? ([["Places", String(v.seats ?? "—")]] as [string, string][]) : []),
            ...(a.activity === "delivery" ? ([["Zone de travail", zone]] as [string, string][]) : []),
            ["Dossier envoyé", formatDateTime(a.submitted_at)],
            ["Dernière décision", formatDateTime(a.reviewed_at)],
            ["Motif", a.review_note || "—"],
          ]}
        />
        <div className="space-y-4">
          <div>
            <p className="mb-2 font-semibold">Pièces exigées</p>
            <ul className="space-y-1">
              {(a.required_documents ?? []).map((k) => (
                <li key={k} className="flex items-center gap-2 text-[13px]">
                  {missing.includes(k) ? (
                    <AlertTriangle size={15} aria-hidden="true" className="text-warning" />
                  ) : (
                    <CheckCircle2 size={15} aria-hidden="true" className="text-success" />
                  )}
                  {DOCUMENT_KIND[k] ?? k}
                  {missing.includes(k) && <span className="text-warning">· manquante</span>}
                </li>
              ))}
            </ul>
          </div>
          <div>
            <p className="mb-2 font-semibold">Contrôle du véhicule sur place</p>
            <p className="text-[13px] text-text-secondary">
              {check
                ? `${check.passed ? "Conforme" : "Non conforme"} le ${formatDateTime(check.checked_at)}${check.note ? ` · ${check.note}` : ""}`
                : a.activity === "vtc"
                  ? "Pas encore fait (obligatoire pour le taxi VTC)."
                  : "Pas encore fait (exigé si le réglage le demande)."}
            </p>
            {pending && (
              <div className="mt-2 flex flex-wrap gap-2">
                <ActionForm
                  action={checkVehicle}
                  label="Véhicule conforme"
                  variant="outline"
                  hidden={{ ...base, passed: "true" }}
                  confirm={{
                    title: "Véhicule conforme ?",
                    body: `Vous confirmez avoir contrôlé sur place le véhicule de ${name}.`,
                  }}
                />
                <ActionForm
                  action={checkVehicle}
                  label="Non conforme"
                  variant="outline"
                  hidden={{ ...base, passed: "false" }}
                  confirm={{ title: "Véhicule non conforme", body: "Le constat est gardé dans le dossier." }}
                  reason={{ label: "Ce qui ne va pas", required: true }}
                />
              </div>
            )}
          </div>
        </div>
      </div>

      {(pending || a.status === "changes_requested") && (
        <div className="mt-6 flex flex-wrap gap-2 border-t border-border pt-4">
          {pending && (
            <ActionForm
              action={reviewActivity}
              label="Valider et activer"
              hidden={{ ...base, decision: "approve" }}
              confirm={{
                title: `Activer « ${label} » pour ${name} ?`,
                body: "Pièces vérifiées, compte de versement présent et, si exigé, véhicule contrôlé. Le partenaire est prévenu.",
              }}
            />
          )}
          {pending && (
            <ActionForm
              action={reviewActivity}
              label="Demander des compléments"
              variant="outline"
              hidden={{ ...base, decision: "request-changes" }}
              confirm={{
                title: "Demander des compléments ?",
                body: "Le partenaire reçoit le motif et peut compléter son dossier.",
              }}
              reason={{ label: "Ce qu'il faut compléter", required: true }}
            />
          )}
          <ActionForm
            action={reviewActivity}
            label="Refuser"
            variant="danger"
            hidden={{ ...base, decision: "reject" }}
            confirm={{
              title: `Refuser le dossier de ${name} ?`,
              body: "Le motif est communiqué au partenaire.",
            }}
            reason={{ label: "Motif du refus", required: true }}
          />
        </div>
      )}
    </Card>
  );
}
