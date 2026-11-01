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
import { DRIVER_STATUS, formatDateTime, formatPhone, statusOf, VEHICLE } from "@/lib/format";

export const metadata = { title: "Livreurs" };

const LIMIT = 20;
const TABS = [
  { value: "pending_review", label: "À valider", query: "review_status=pending_review" },
  { value: "approved", label: "Validés", query: "review_status=approved" },
  { value: "suspended", label: "Suspendus", query: "suspended=true" },
  { value: "rejected", label: "Refusés", query: "review_status=rejected" },
];

type Props = { searchParams: Promise<{ review_status?: string; suspended?: string; offset?: string }> };

export default async function DriversPage({ searchParams }: Props) {
  const sp = await searchParams;
  const suspended = sp.suspended === "true";
  const review = suspended ? undefined : (sp.review_status ?? "pending_review");
  const current = suspended ? "suspended" : (review ?? "pending_review");
  const offset = Number(sp.offset ?? 0) || 0;

  let page: { items: Schemas["AdminDriver"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/drivers", {
      query: { review_status: review, suspended: suspended || undefined, limit: LIMIT, offset },
    });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        title="Livreurs"
        description="Un livreur ne reçoit de missions qu'après validation de son dossier (pièce d'identité et permis)."
      />
      <FilterTabs
        current={current}
        tabs={TABS.map((t) => ({ value: t.value, label: t.label, href: `/drivers?${t.query}` }))}
      />
      {page.items.length === 0 ? (
        <EmptyState message="Aucun livreur dans cette liste." />
      ) : (
        <Table head={["Livreur", "Véhicule", "Documents", "Statut", "Candidature", ""]}>
          {page.items.map((d) => (
            <tr key={d.user_id}>
              <Td>
                <p className="font-semibold">{d.first_name || "—"}</p>
                <p className="text-[13px] text-text-muted">{formatPhone(d.phone)}</p>
              </Td>
              <Td>
                {VEHICLE[d.vehicle_type] ?? d.vehicle_type} · {d.vehicle_plate}
              </Td>
              <Td>{d.documents.length}</Td>
              <Td>
                <StatusBadge {...statusOf(DRIVER_STATUS, d.status)} />
              </Td>
              <Td>{formatDateTime(d.created_at)}</Td>
              <Td>
                <Link href={`/drivers/${d.user_id}`} className="font-semibold text-secondary hover:underline">
                  Ouvrir le dossier
                </Link>
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/drivers"
        params={suspended ? { suspended: "true" } : { review_status: review }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
