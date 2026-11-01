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
import { formatDateTime, formatXOF, ORDER_STATUS, statusOf } from "@/lib/format";

export const metadata = { title: "Commandes" };

const LIMIT = 25;
const TABS = [
  { value: "", label: "Toutes" },
  { value: "awaiting_seller", label: "En attente de la boutique" },
  { value: "awaiting_driver", label: "Sans livreur" },
  { value: "picked_up", label: "En livraison" },
  { value: "delivery_failed", label: "Livraison échouée" },
  { value: "cancelled", label: "Annulées" },
];

type Props = { searchParams: Promise<{ status?: string; number?: string; offset?: string }> };

export default async function OrdersPage({ searchParams }: Props) {
  const sp = await searchParams;
  const status = sp.status ?? "";
  const number = sp.number?.replace(/\D/g, "") ?? "";
  const offset = Number(sp.offset ?? 0) || 0;

  let page: { items: Schemas["AdminOrder"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/orders", { query: { status, number, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        title="Commandes"
        actions={
          <form className="flex gap-2" action="/orders">
            <label className="sr-only" htmlFor="number">
              Numéro de commande
            </label>
            <input
              id="number"
              name="number"
              defaultValue={number}
              placeholder="N° (ex. 123)"
              inputMode="numeric"
              className="h-10 w-40 rounded-full border border-border-input bg-surface px-4"
            />
            <button className="h-10 rounded-full bg-tertiary px-5 text-sm font-bold text-white">
              Rechercher
            </button>
          </form>
        }
      />
      <FilterTabs
        current={status}
        tabs={TABS.map((t) => ({ ...t, href: t.value ? `/orders?status=${t.value}` : "/orders" }))}
      />
      {page.items.length === 0 ? (
        <EmptyState message="Aucune commande dans cette liste." />
      ) : (
        <Table head={["Commande", "Mode", "Total", "Statut", "Créée le"]}>
          {page.items.map((o) => (
            <tr key={o.id}>
              <Td>
                <Link href={`/orders/${o.id}`} className="font-semibold text-secondary hover:underline">
                  {o.reference}
                </Link>
              </Td>
              <Td>{o.fulfillment === "delivery" ? "Livraison" : "Retrait"}</Td>
              <Td className="font-semibold">{formatXOF(o.total_xof)}</Td>
              <Td>
                <StatusBadge {...statusOf(ORDER_STATUS, o.status)} />
              </Td>
              <Td>{formatDateTime(o.created_at)}</Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/orders"
        params={{ status, number }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
