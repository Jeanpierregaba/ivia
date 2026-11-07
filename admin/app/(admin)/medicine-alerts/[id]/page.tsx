import { ChevronLeft, CreditCard, MessageSquareReply, Pill } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Card, CardTitle, DefinitionList, ErrorState, PageHeader, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import {
  formatDateTime,
  formatXOF,
  MEDICINE_ALERT_STATUS,
  MEDICINE_PAYMENT_STATUS,
  statusOf,
} from "@/lib/format";

export const metadata = { title: "Alerte médicament" };

export default async function MedicineAlertPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  let a: Schemas["AdminMedicineAlert"];
  try {
    a = await api<Schemas["AdminMedicineAlert"]>(`/v1/admin/medicine-alerts/${encodeURIComponent(id)}`);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <Link
        href="/medicine-alerts"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Alertes médicament
      </Link>
      <PageHeader overline="Santé" title="Détail de l'alerte" highlight="alerte" />
      <div className="grid grid-cols-2 gap-4">
        <Card>
          <CardTitle icon={<Pill size={18} aria-hidden="true" />}>Demande</CardTitle>
          <div className="mb-3">
            <StatusBadge {...statusOf(MEDICINE_ALERT_STATUS, a.status)} />
          </div>
          <DefinitionList
            items={[
              [
                "Produits",
                a.items.map((i) => `${i.quantity} × ${i.name}`).join(", ") || "Ordonnance en photo",
              ],
              ["Photos", String(a.photos.length)],
              ["Note du patient", a.note || "—"],
              ["Générique accepté", a.generic_accepted ? "Oui" : "Non"],
              ["Rayon", `${(a.radius_m / 1000).toLocaleString("fr-FR")} km`],
              [
                "Sollicitées / vues / réponses",
                `${a.stats.notified} / ${a.stats.seen} / ${a.stats.responded}`,
              ],
              ["Fin de la recherche", formatDateTime(a.search_ends_at)],
              ["Créée", formatDateTime(a.created_at)],
            ]}
          />
        </Card>
        <Card>
          <CardTitle icon={<CreditCard size={18} aria-hidden="true" />}>Paiements</CardTitle>
          {a.payments.length === 0 ? (
            <p className="text-text-secondary">Aucun paiement.</p>
          ) : (
            <ul className="space-y-2">
              {a.payments.map((p) => (
                <li
                  key={p.id}
                  className="flex items-center justify-between rounded-card bg-background px-4 py-3"
                >
                  <span>
                    <span className="font-semibold">{p.purpose === "unlock" ? "Déblocage" : "Commande"}</span>
                    <span className="block text-[13px] text-text-muted">{formatDateTime(p.created_at)}</span>
                  </span>
                  <span className="flex items-center gap-3">
                    <span className="font-semibold">{formatXOF(p.amount_xof)}</span>
                    <StatusBadge {...statusOf(MEDICINE_PAYMENT_STATUS, p.status)} />
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
      <Card className="mt-4">
        <CardTitle icon={<MessageSquareReply size={18} aria-hidden="true" />}>
          Réponses des pharmacies ({a.responses.length})
        </CardTitle>
        {a.responses.length === 0 ? (
          <p className="text-text-secondary">Aucune réponse pour le moment.</p>
        ) : (
          <ul className="space-y-2">
            {a.responses.map((r) => (
              <li key={r.id} className="rounded-card bg-background px-4 py-3">
                <div className="flex items-center justify-between">
                  <span className="font-semibold">
                    {r.label} · {(r.distance_m / 1000).toLocaleString("fr-FR", { maximumFractionDigits: 1 })}{" "}
                    km
                  </span>
                  <span className="font-semibold">{formatXOF(r.total_xof)}</span>
                </div>
                <p className="text-[13px] text-text-muted">
                  {r.available_count} / {r.line_count} disponibles
                  {r.prescription_required && " · ordonnance"}
                  {r.unlocked && " · débloquée"}
                  {r.status === "withdrawn" && " · retirée"} · {formatDateTime(r.responded_at)}
                </p>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}
