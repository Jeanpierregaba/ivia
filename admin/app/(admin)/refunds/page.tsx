import Link from "next/link";

import { ActionForm } from "@/components/action-form";
import { EmptyState, ErrorState, PageHeader, Pagination, StatusBadge, Table, Td } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, formatXOF, ORDER_STATUS, statusOf } from "@/lib/format";
import { orderAction } from "../orders/actions";

export const metadata = { title: "Remboursements" };

const LIMIT = 25;

export default async function RefundsPage({ searchParams }: { searchParams: Promise<{ offset?: string }> }) {
  const offset = Number((await searchParams).offset ?? 0) || 0;
  let page: { items: Schemas["AdminOrder"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/refund-queue", { query: { limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Argent"
        title="Remboursements à effectuer"
        highlight="Remboursements"
        description="Commandes annulées après paiement ou revenues en boutique, pas encore remboursées."
      />
      {page.items.length === 0 ? (
        <EmptyState
          title="Tout est à jour"
          message="Aucun remboursement en attente : chaque acheteur concerné a été remboursé."
        />
      ) : (
        <Table head={["Commande", "Statut", "À rembourser", "Depuis", ""]}>
          {page.items.map((o) => (
            <tr key={o.id}>
              <Td>
                <Link href={`/orders/${o.id}`} className="font-semibold text-secondary hover:underline">
                  {o.reference}
                </Link>
                {o.cancel_reason && <p className="text-[13px] text-text-muted">{o.cancel_reason}</p>}
              </Td>
              <Td>
                <StatusBadge {...statusOf(ORDER_STATUS, o.status)} />
              </Td>
              <Td className="font-bold text-primary-strong">{formatXOF(o.refund_due_xof)}</Td>
              <Td>{formatDateTime(o.cancelled_at ?? o.updated_at)}</Td>
              <Td>
                <ActionForm
                  action={orderAction}
                  label="Rembourser"
                  hidden={{ id: o.id, action: "refund" }}
                  confirm={{
                    title: `Rembourser ${formatXOF(o.refund_due_xof)} ?`,
                    body: `Transfert Mobile Money vers le numéro qui a payé la commande ${o.reference}.`,
                  }}
                  reason={{ label: "Motif (journal)" }}
                />
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/refunds"
        params={{}}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
