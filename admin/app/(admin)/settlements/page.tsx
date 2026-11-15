import { ChevronRight, Plus } from "lucide-react";
import Link from "next/link";

import {
  buttonClass,
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
import { formatDateTime, formatXOF, frDate, SETTLEMENT_STATUS, statusOf } from "@/lib/format";

export const metadata = { title: "Relevés marchands" };

const LIMIT = 25;
const TABS = [
  { value: "open", label: "À régler" },
  { value: "settled", label: "Réglés" },
  { value: "", label: "Tous" },
];

type Props = { searchParams: Promise<{ status?: string; offset?: string }> };

export default async function SettlementsPage({ searchParams }: Props) {
  const sp = await searchParams;
  const status = sp.status ?? "open";
  const offset = Number(sp.offset ?? 0) || 0;

  let page: { items: Schemas["Settlement"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/settlements", { query: { status, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Argent"
        title="Relevés et reversements aux marchands"
        highlight="reversements"
        description="Un relevé regroupe les commandes remises d'une boutique sur une période : produits encaissés, commission ivia, net à reverser."
        actions={
          <Link href="/settlements/new" className={buttonClass("imperial")}>
            <Plus size={18} aria-hidden="true" /> Nouveau relevé
          </Link>
        }
      />
      <FilterTabs
        current={status}
        tabs={TABS.map((t) => ({ ...t, href: `/settlements?status=${t.value}` }))}
      />
      {page.items.length === 0 ? (
        <EmptyState
          title={status === "open" ? "Rien à régler" : "Rien à afficher"}
          message={
            status === "open" ? "Aucun relevé en attente de reversement." : "Aucun relevé dans cette liste."
          }
        />
      ) : (
        <Table
          head={[
            "Boutique",
            "Période",
            "Commandes",
            "Encaissé",
            "Commission",
            "Net à reverser",
            "Statut",
            "",
          ]}
        >
          {page.items.map((s) => (
            <tr key={s.id}>
              <Td>
                <p className="font-semibold">{s.shop_name || "—"}</p>
                <p className="text-[13px] text-text-muted">Créé le {formatDateTime(s.created_at)}</p>
              </Td>
              <Td>
                {frDate(s.period_start)} → {frDate(s.period_end)}
              </Td>
              <Td>{s.orders_count}</Td>
              <Td>{formatXOF(s.gross_xof)}</Td>
              <Td>{formatXOF(s.commission_xof)}</Td>
              <Td className="font-bold text-primary-strong">{formatXOF(s.net_xof)}</Td>
              <Td>
                <StatusBadge {...statusOf(SETTLEMENT_STATUS, s.status)} />
              </Td>
              <Td>
                <Link
                  href={`/settlements/${s.id}`}
                  aria-label={`Ouvrir le relevé de ${s.shop_name}`}
                  className="text-secondary"
                >
                  <ChevronRight size={18} aria-hidden="true" />
                </Link>
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/settlements"
        params={{ status }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
