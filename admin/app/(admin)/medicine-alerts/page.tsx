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
import { formatDateTime, MEDICINE_ALERT_STATUS, statusOf } from "@/lib/format";

export const metadata = { title: "Alertes médicament" };

const LIMIT = 20;
const TABS = [
  { value: "", label: "Toutes" },
  { value: "searching", label: "En recherche" },
  { value: "answered", label: "Avec réponses" },
  { value: "no_response", label: "Sans réponse" },
  { value: "unlocked", label: "Débloquées" },
  { value: "fulfilled", label: "Terminées" },
  { value: "cancelled", label: "Annulées" },
];

function alertTitle(a: Schemas["AdminMedicineAlert"]): string {
  const [first] = a.items;
  if (!first) return "Ordonnance en photo";
  return a.items.length === 1 ? first.name : `${first.name} + ${a.items.length - 1}`;
}

export default async function MedicineAlertsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; offset?: string }>;
}) {
  const sp = await searchParams;
  const status = sp.status || undefined;
  const offset = Number(sp.offset ?? 0) || 0;
  let page: { items: Schemas["AdminMedicineAlert"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/medicine-alerts", { query: { status, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Santé"
        title="Les alertes médicament"
        highlight="alertes"
        description="Suivi des recherches des patients : pharmacies sollicitées, réponses et déblocages."
      />
      <FilterTabs
        current={status ?? ""}
        tabs={TABS.map((t) => ({
          value: t.value,
          label: t.label,
          href: t.value ? `/medicine-alerts?status=${t.value}` : "/medicine-alerts",
        }))}
      />
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucune alerte dans cette liste pour le moment." />
      ) : (
        <Table head={["Demande", "Rayon", "Sollicitées", "Vues", "Réponses", "Statut", "Créée", ""]}>
          {page.items.map((a) => (
            <tr key={a.id}>
              <Td>
                <span className="font-semibold">{alertTitle(a)}</span>
              </Td>
              <Td>{(a.radius_m / 1000).toLocaleString("fr-FR")} km</Td>
              <Td>{a.stats.notified}</Td>
              <Td>{a.stats.seen}</Td>
              <Td>{a.stats.responded}</Td>
              <Td>
                <StatusBadge {...statusOf(MEDICINE_ALERT_STATUS, a.status)} />
              </Td>
              <Td>{formatDateTime(a.created_at)}</Td>
              <Td>
                <Link
                  href={`/medicine-alerts/${a.id}`}
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
        basePath="/medicine-alerts"
        params={{ status }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
