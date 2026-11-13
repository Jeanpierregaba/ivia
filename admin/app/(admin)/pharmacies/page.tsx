import { ChevronRight, Search } from "lucide-react";
import Link from "next/link";

import {
  Avatar,
  Card,
  EmptyState,
  ErrorState,
  FilterTabs,
  fieldClass,
  PageHeader,
  Pagination,
  StatusBadge,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, formatPhone, formatXOF, PHARMACY_STATUS, statusOf } from "@/lib/format";

export const metadata = { title: "Pharmacies" };

const LIMIT = 20;
const TABS = [
  { value: "pending_review", label: "À valider", query: "review_status=pending_review" },
  { value: "changes_requested", label: "À compléter", query: "review_status=changes_requested" },
  { value: "approved", label: "Validées", query: "review_status=approved" },
  { value: "suspended", label: "Suspendues", query: "suspended_only=true" },
  { value: "rejected", label: "Refusées", query: "review_status=rejected" },
];

type Props = {
  searchParams: Promise<{ review_status?: string; suspended_only?: string; q?: string; offset?: string }>;
};

export default async function PharmaciesPage({ searchParams }: Props) {
  const sp = await searchParams;
  const suspended = sp.suspended_only === "true";
  const review = suspended ? undefined : (sp.review_status ?? "pending_review");
  const current = suspended ? "suspended" : (review ?? "pending_review");
  const offset = Number(sp.offset ?? 0) || 0;
  const q = sp.q?.trim() || undefined;

  let page: { items: Schemas["AdminPharmacy"][]; next_offset: number | null };
  let o: Schemas["PharmacyOverview"];
  try {
    [page, o] = await Promise.all([
      api<{ items: Schemas["AdminPharmacy"][]; next_offset: number | null }>("/v1/admin/pharmacies", {
        query: { review_status: review, suspended_only: suspended || undefined, q, limit: LIMIT, offset },
      }),
      api<Schemas["PharmacyOverview"]>("/v1/admin/pharmacy/overview"),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const tiles: [string, string][] = [
    ["Pharmacies validées", String(o.approved)],
    ["Joignables maintenant", String(o.reachable)],
    ["Alertes (30 jours)", String(o.alerts)],
    ["Alertes sans réponse", String(o.alerts_without_response)],
    ["Déblocages", String(o.unlocked)],
    ["Revenus des déblocages", formatXOF(o.unlock_revenue_xof)],
  ];

  return (
    <>
      <PageHeader
        overline="Santé"
        title="Les pharmacies et leurs dossiers"
        highlight="pharmacies"
        description="Une pharmacie ne reçoit d'alertes qu'après validation de ses trois pièces."
      />
      <div className="mb-4 grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3">
        {tiles.map(([label, value]) => (
          <Card key={label}>
            <p className="text-[22px] font-bold leading-7">{value}</p>
            <p className="mt-1 text-[12px] text-text-muted">{label}</p>
          </Card>
        ))}
      </div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <FilterTabs
          current={current}
          tabs={TABS.map((t) => ({ value: t.value, label: t.label, href: `/pharmacies?${t.query}` }))}
        />
        <form action="/pharmacies" role="search" className="relative">
          {review && <input type="hidden" name="review_status" value={review} />}
          {suspended && <input type="hidden" name="suspended_only" value="true" />}
          <Search
            size={16}
            aria-hidden="true"
            className="absolute left-3 top-1/2 -translate-y-1/2 text-text-muted"
          />
          <input
            name="q"
            defaultValue={q}
            aria-label="Rechercher une pharmacie"
            placeholder="Nom de la pharmacie"
            className={`${fieldClass} w-72 pl-9`}
          />
        </form>
      </div>
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucune pharmacie dans cette liste pour le moment." />
      ) : (
        <Table head={["Pharmacie", "Responsable", "Pièces", "Statut", "Inscription", ""]}>
          {page.items.map((p) => (
            <tr key={p.id}>
              <Td>
                <div className="flex items-center gap-3">
                  <Avatar name={p.name || "?"} tone="cobalt" />
                  <div>
                    <p className="font-semibold">{p.name}</p>
                    <p className="text-[13px] text-text-muted">{p.address_text}</p>
                  </div>
                </div>
              </Td>
              <Td>
                {p.owner_first_name || "—"}
                <p className="text-[13px] text-text-muted">{formatPhone(p.owner_phone)}</p>
              </Td>
              <Td>{p.documents.length} / 3</Td>
              <Td>
                <StatusBadge {...statusOf(PHARMACY_STATUS, p.status)} />
              </Td>
              <Td>{formatDateTime(p.created_at)}</Td>
              <Td>
                <Link
                  href={`/pharmacies/${p.id}`}
                  className="inline-flex items-center gap-1 font-semibold text-secondary hover:underline"
                >
                  Ouvrir <ChevronRight size={16} aria-hidden="true" />
                </Link>
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/pharmacies"
        params={suspended ? { suspended_only: "true", q } : { review_status: review, q }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
