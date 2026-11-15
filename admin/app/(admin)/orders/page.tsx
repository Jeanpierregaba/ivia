import { ChevronRight, Search } from "lucide-react";
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
        overline="Suivi"
        title="Toutes les commandes"
        highlight="commandes"
        description="Du paiement à la remise : chaque étape est horodatée et consultable."
        actions={
          <form className="flex gap-2" action="/orders" role="search">
            <label className="sr-only" htmlFor="number">
              Numéro de commande
            </label>
            <span className="relative">
              <Search
                size={16}
                aria-hidden="true"
                className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-text-muted"
              />
              <input
                id="number"
                name="number"
                defaultValue={number}
                placeholder="N° de commande"
                inputMode="numeric"
                className="h-11 w-52 rounded-full border border-border-input bg-surface pl-10 pr-4 outline-none focus:border-2 focus:border-primary"
              />
            </span>
            <button className={buttonClass("primary")}>Rechercher</button>
          </form>
        }
      />
      <FilterTabs
        current={status}
        tabs={TABS.map((t) => ({ ...t, href: t.value ? `/orders?status=${t.value}` : "/orders" }))}
      />
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucune commande ne correspond à ce filtre." />
      ) : (
        <Table head={["Commande", "Mode", "Total", "Statut", "Créée le", ""]}>
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
              <Td>
                <Link
                  href={`/orders/${o.id}`}
                  aria-label={`Ouvrir la commande ${o.reference}`}
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
        basePath="/orders"
        params={{ status, number }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
