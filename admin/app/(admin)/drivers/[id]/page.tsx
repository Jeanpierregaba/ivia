import { AlertTriangle, ChevronLeft, FileText, Gavel, IdCard } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ActionForm } from "@/components/action-form";
import { Avatar, Card, CardTitle, DefinitionList, ErrorState, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { DOCUMENT_KIND, DRIVER_STATUS, formatDateTime, formatPhone, statusOf, VEHICLE } from "@/lib/format";
import { reviewDriver } from "../actions";

export const metadata = { title: "Dossier livreur" };

const REQUIRED: Schemas["Document"]["kind"][] = ["id_card", "driving_license"];

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

  const kinds = new Set(d.documents.map((doc) => doc.kind));
  const missing = REQUIRED.filter((k) => !kinds.has(k)).map((k) => DOCUMENT_KIND[k]);
  const hidden = (decision: string) => ({ id: d.user_id, decision });
  const name = d.first_name || "ce livreur";

  return (
    <>
      <Link
        href="/drivers"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Livreurs
      </Link>
      <header className="mb-6 flex items-center gap-5 rounded-field bg-tertiary p-6 text-white">
        <Avatar name={d.first_name || "?"} tone="cobalt" size={64} />
        <div className="min-w-0 flex-1">
          <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-white/60">
            Dossier livreur
          </p>
          <h1 className="text-[28px] font-bold leading-8 tracking-[-0.02em]">
            {d.first_name || "Sans prénom"}
          </h1>
          <p className="mt-1 text-white/75">
            {VEHICLE[d.vehicle_type] ?? d.vehicle_type}
            {d.vehicle_plate && ` · ${d.vehicle_plate}`} · {formatPhone(d.phone)}
          </p>
        </div>
        <span className="rounded-full bg-surface">
          <StatusBadge {...statusOf(DRIVER_STATUS, d.status)} />
        </span>
      </header>

      <div className="grid grid-cols-2 gap-4">
        <Card>
          <CardTitle icon={<IdCard size={18} aria-hidden="true" />}>Identité et véhicule</CardTitle>
          <DefinitionList
            items={[
              ["Prénom", d.first_name || "—"],
              ["Téléphone", formatPhone(d.phone)],
              ["Véhicule", VEHICLE[d.vehicle_type] ?? d.vehicle_type],
              ["Immatriculation", d.vehicle_plate || "—"],
              ["Description", d.vehicle_description || "—"],
              ["Candidature", formatDateTime(d.created_at)],
              ["Dernière décision", formatDateTime(d.reviewed_at)],
              ["Note", d.review_note || d.suspension_reason || "—"],
            ]}
          />
        </Card>

        <Card>
          <CardTitle icon={<FileText size={18} aria-hidden="true" />}>Documents</CardTitle>
          {d.documents.length === 0 ? (
            <p className="text-text-secondary">Aucun document déposé.</p>
          ) : (
            <ul className="space-y-2">
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
          {missing.length > 0 && (
            <p
              role="status"
              className="mt-4 flex items-start gap-2 rounded-card bg-[#FBEFE3] px-4 py-3 text-[13px] text-warning"
            >
              <AlertTriangle size={16} aria-hidden="true" className="mt-px shrink-0" />
              Manquant pour valider : {missing.join(", ")}.
            </p>
          )}
        </Card>
      </div>

      <Card className="mt-4">
        <CardTitle icon={<Gavel size={18} aria-hidden="true" />}>Décision</CardTitle>
        <div className="flex flex-wrap gap-2">
          {(d.review_status === "pending_review" || d.review_status === "rejected") && (
            <ActionForm
              action={reviewDriver}
              label="Valider et activer"
              hidden={hidden("approve")}
              confirm={{
                title: `Activer le compte de ${name} ?`,
                body: "Après vérification des documents, le livreur pourra passer en ligne et recevoir des missions.",
              }}
            />
          )}
          {d.review_status === "pending_review" && (
            <ActionForm
              action={reviewDriver}
              label="Refuser"
              variant="outline"
              hidden={hidden("reject")}
              confirm={{
                title: `Refuser la candidature de ${name} ?`,
                body: "Le motif est communiqué au candidat, qui peut corriger son dossier.",
              }}
              reason={{ label: "Motif du refus", required: true }}
            />
          )}
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
              confirm={{ title: `Rétablir ${name} ?`, body: "Le livreur pourra de nouveau passer en ligne." }}
            />
          )}
        </div>
      </Card>
    </>
  );
}
