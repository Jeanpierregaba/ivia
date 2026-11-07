import { AlertTriangle, ChevronLeft, FileText, Gavel, IdCard, Store, Wallet } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ActionForm } from "@/components/action-form";
import { Card, CardTitle, DefinitionList, ErrorState, PageHeader, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import {
  BUSINESS_DOCUMENT,
  BUSINESS_SECTOR,
  BUSINESS_STATUS,
  formatDateTime,
  formatPhone,
  statusOf,
} from "@/lib/format";
import { reviewSpace } from "../actions";

export const metadata = { title: "Dossier Ivia Business" };

export default async function BusinessSpacePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  let s: Schemas["BusinessSpace"];
  try {
    s = await api<Schemas["BusinessSpace"]>(`/v1/admin/business/spaces/${encodeURIComponent(id)}`);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const d = s.details;
  const hidden = (decision: string) => ({ id: s.id, decision });
  const missing = s.missing_documents.map((k) => BUSINESS_DOCUMENT[k] ?? k);
  const owner = s.owner ? `${s.owner.first_name} ${s.owner.last_name}`.trim() : "—";

  return (
    <>
      <Link
        href="/business"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Ivia Business
      </Link>
      <PageHeader overline={BUSINESS_SECTOR[s.sector] ?? s.sector} title={s.name} />
      <div className="mb-4">
        <StatusBadge {...statusOf(BUSINESS_STATUS, s.status)} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Card>
          <CardTitle icon={<Store size={18} aria-hidden="true" />}>Activité</CardTitle>
          <DefinitionList
            items={[
              ["Secteur", BUSINESS_SECTOR[s.sector] ?? s.sector],
              ["Description", d.description || "—"],
              ["Téléphone", formatPhone(d.phone)],
              ["Adresse", d.address_text || "—"],
              ["RCCM", d.rccm || "—"],
              ["Zone", d.zone || "—"],
              ["Métiers", d.trades?.join(", ") || "—"],
              ["Cuisine", d.cuisine || "—"],
              ["Horaires", d.opening_hours || "—"],
              ["Envoyé le", formatDateTime(s.submitted_at)],
              ["Dernière décision", formatDateTime(s.reviewed_at)],
              ["Motif", s.status_reason || "—"],
            ]}
          />
          {s.photo_urls.length > 0 && (
            <div className="mt-4 flex flex-wrap gap-2">
              {s.photo_urls.map((u) => (
                // eslint-disable-next-line @next/next/no-img-element
                <img key={u} src={u} alt="" className="size-20 rounded-card object-cover" />
              ))}
            </div>
          )}
        </Card>
        <div className="space-y-4">
          <Card>
            <CardTitle icon={<IdCard size={18} aria-hidden="true" />}>
              Identité et compte de versement
            </CardTitle>
            <p className="mb-3 text-[13px] text-text-muted">
              Vérifiez que l&apos;identité correspond au titulaire du compte de versement.
            </p>
            <DefinitionList
              items={[
                ["Titulaire du compte ivia", owner],
                ["Téléphone du compte", formatPhone(s.owner?.phone)],
                ["Titulaire du versement", s.payout?.holder || "—"],
                ["Numéro de versement", formatPhone(s.payout?.phone)],
                [
                  "Opérateur",
                  s.payout?.operator === "tmoney" ? "Yas (T-Money)" : s.payout ? "Moov (Flooz)" : "—",
                ],
              ]}
            />
          </Card>
          <Card>
            <CardTitle icon={<FileText size={18} aria-hidden="true" />}>Justificatifs</CardTitle>
            {s.documents.length === 0 ? (
              <p className="text-text-secondary">Aucun justificatif déposé.</p>
            ) : (
              <ul className="space-y-2">
                {s.documents.map((doc) => (
                  <li
                    key={doc.kind}
                    className="flex items-center justify-between rounded-card bg-background px-4 py-3"
                  >
                    <span className="font-semibold">{BUSINESS_DOCUMENT[doc.kind] ?? doc.kind}</span>
                    {doc.url && (
                      // Lien temporaire (10 min) vers le compartiment privé.
                      <a
                        href={doc.url}
                        target="_blank"
                        rel="noreferrer"
                        className="font-semibold text-secondary hover:underline"
                      >
                        Consulter
                      </a>
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
            {s.shop_id && (
              <p className="mt-3 text-[13px]">
                <Link
                  href={`/shops/${s.shop_id}`}
                  className="inline-flex items-center gap-1 font-semibold text-secondary hover:underline"
                >
                  <Wallet size={14} aria-hidden="true" /> Voir la fiche boutique
                </Link>
              </p>
            )}
          </Card>
        </div>
      </div>
      <Card className="mt-4">
        <CardTitle icon={<Gavel size={18} aria-hidden="true" />}>Décision</CardTitle>
        <div className="flex flex-wrap gap-2">
          {s.status === "pending_review" && (
            <>
              <ActionForm
                action={reviewSpace}
                label="Valider et activer"
                hidden={hidden("approve")}
                confirm={{
                  title: `Activer ${s.name} ?`,
                  body: "L'identité correspond au titulaire du versement. L'espace devient actif et visible des clients.",
                }}
              />
              <ActionForm
                action={reviewSpace}
                label="Demander des compléments"
                variant="outline"
                hidden={hidden("request_changes")}
                confirm={{
                  title: "Demander des compléments ?",
                  body: "Le professionnel reçoit le motif et corrige son dossier.",
                }}
                reason={{ label: "Ce qu'il faut compléter", required: true }}
              />
              <ActionForm
                action={reviewSpace}
                label="Refuser"
                variant="danger"
                hidden={hidden("reject")}
                confirm={{ title: `Refuser ${s.name} ?`, body: "Le motif est communiqué au professionnel." }}
                reason={{ label: "Motif du refus", required: true }}
              />
            </>
          )}
          {s.status === "active" && (
            <ActionForm
              action={reviewSpace}
              label="Suspendre"
              variant="danger"
              hidden={hidden("suspend")}
              confirm={{
                title: `Suspendre ${s.name} ?`,
                body: "L'espace n'est plus accessible ni visible des clients.",
              }}
              reason={{ label: "Motif de la suspension", required: true }}
            />
          )}
          {s.status === "suspended" && (
            <ActionForm
              action={reviewSpace}
              label="Rétablir"
              variant="outline"
              hidden={hidden("reinstate")}
              confirm={{ title: `Rétablir ${s.name} ?`, body: "L'espace redevient actif." }}
            />
          )}
          {!["pending_review", "active", "suspended"].includes(s.status) && (
            <p className="text-text-secondary">En attente du professionnel : aucune décision à prendre.</p>
          )}
        </div>
      </Card>
    </>
  );
}
