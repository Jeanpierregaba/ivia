import { AlertTriangle, ChevronLeft, FileText, Gavel, Store } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Avatar, Card, CardTitle, DefinitionList, ErrorState, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { DOCUMENT_KIND, formatDateTime, formatPhone, SHOP_STATUS, statusOf } from "@/lib/format";
import { missingMerchantDocuments, ShopActions } from "../shop-actions";

export const metadata = { title: "Dossier boutique" };

export default async function ShopPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  let s: Schemas["Shop"];
  try {
    // Ouverture du dossier : l'API joint des liens temporaires vers les pièces du marchand.
    s = await api<Schemas["Shop"]>(`/v1/admin/shops/${encodeURIComponent(id)}`);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const missing = missingMerchantDocuments(s).map((k) => DOCUMENT_KIND[k] ?? k);

  return (
    <>
      <Link
        href="/shops"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Boutiques
      </Link>
      <header className="mb-6 flex items-center gap-5 rounded-field bg-tertiary p-6 text-white">
        <Avatar name={s.name} tone="imperial" size={64} />
        <div className="min-w-0 flex-1">
          <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-white/60">
            Dossier boutique
          </p>
          <h1 className="text-[24px] font-bold leading-8 tracking-[-0.02em]">{s.name}</h1>
          <p className="mt-1 text-white/75">
            {s.category_name || "Sans catégorie"}
            {s.neighborhood_name && ` · ${s.neighborhood_name}`} · {formatPhone(s.phone)}
          </p>
        </div>
        <span className="rounded-full bg-surface">
          <StatusBadge {...statusOf(SHOP_STATUS, s.status)} />
        </span>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardTitle icon={<Store size={18} aria-hidden="true" />}>Boutique</CardTitle>
          <DefinitionList
            items={[
              ["Nom", s.name],
              ["Catégorie", s.category_name || "—"],
              ["Téléphone", formatPhone(s.phone)],
              ["Adresse", s.address_text],
              ["Quartier", s.neighborhood_name || "—"],
              ["Commandes", s.accepting_orders ? "Acceptées" : "En pause"],
              ["Créée le", formatDateTime(s.created_at)],
              ["Dernière décision", formatDateTime(s.reviewed_at)],
              ["Motif", s.status_reason || "—"],
            ]}
          />
          {s.description && <p className="mt-4 text-text-secondary">{s.description}</p>}
        </Card>

        <Card>
          <CardTitle icon={<FileText size={18} aria-hidden="true" />}>Pièces du marchand</CardTitle>
          {s.merchant_documents.length === 0 ? (
            <p className="text-text-secondary">Aucune pièce déposée.</p>
          ) : (
            <ul className="space-y-2">
              {s.merchant_documents.map((doc) => (
                <li
                  key={doc.id}
                  className="flex items-center justify-between rounded-card bg-background px-4 py-3"
                >
                  <span className="flex items-center gap-2 font-semibold">
                    <FileText size={16} aria-hidden="true" className="text-secondary" />
                    {DOCUMENT_KIND[doc.kind] ?? doc.kind}
                  </span>
                  {doc.url ? (
                    // Lien temporaire vers le compartiment privé.
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
              Manquant pour publier : {missing.join(", ")}. Le marchand la dépose depuis son app.
            </p>
          )}
          <p className="mt-4 text-[13px] text-text-muted">
            Les pièces valent pour toutes les boutiques de ce marchand.
          </p>
        </Card>
      </div>

      <Card className="mt-4">
        <CardTitle icon={<Gavel size={18} aria-hidden="true" />}>Décision</CardTitle>
        <ShopActions shop={s} />
      </Card>
    </>
  );
}
