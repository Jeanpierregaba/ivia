import { ChevronRight } from "lucide-react";
import Link from "next/link";

import {
  EmptyState,
  ErrorState,
  FilterTabs,
  PageHeader,
  Pagination,
  StatusBadge,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { BUSINESS_SECTOR, BUSINESS_STATUS, formatDateTime, formatPhone, statusOf } from "@/lib/format";

export const metadata = { title: "Ivia Business" };

const LIMIT = 20;
const TABS = [
  { value: "pending_review", label: "À examiner" },
  { value: "changes_requested", label: "À compléter" },
  { value: "active", label: "Actifs" },
  { value: "rejected", label: "Refusés" },
  { value: "suspended", label: "Suspendus" },
  { value: "draft", label: "Brouillons" },
];

export default async function BusinessPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; offset?: string }>;
}) {
  const sp = await searchParams;
  const status = sp.status || "pending_review";
  const offset = Number(sp.offset ?? 0) || 0;
  let page: { items: Schemas["BusinessSpace"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/business/spaces", { query: { status, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Réseau"
        title="Les dossiers Ivia Business"
        highlight="dossiers"
        description="Boutiques, agences, artisans et restaurants. Un espace n'est visible des clients qu'après validation."
      />
      <FilterTabs
        current={status}
        tabs={TABS.map((t) => ({ value: t.value, label: t.label, href: `/business?status=${t.value}` }))}
      />
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucun dossier dans cette liste pour le moment." />
      ) : (
        <Table head={["Espace", "Secteur", "Titulaire", "Statut", "Envoyé le", ""]}>
          {page.items.map((s) => (
            <tr key={s.id}>
              <Td>
                <span className="font-semibold">{s.name}</span>
              </Td>
              <Td>{BUSINESS_SECTOR[s.sector] ?? s.sector}</Td>
              <Td>
                {s.owner?.first_name} {s.owner?.last_name}
                <p className="text-[13px] text-text-muted">{formatPhone(s.owner?.phone)}</p>
              </Td>
              <Td>
                <StatusBadge {...statusOf(BUSINESS_STATUS, s.status)} />
              </Td>
              <Td>{formatDateTime(s.submitted_at)}</Td>
              <Td>
                <Link
                  href={`/business/${s.id}`}
                  className="inline-flex items-center gap-1 font-semibold text-secondary hover:underline"
                >
                  Examiner <ChevronRight size={16} aria-hidden="true" />
                </Link>
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/business"
        params={{ status }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
