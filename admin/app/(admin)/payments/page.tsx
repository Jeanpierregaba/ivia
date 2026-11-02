import { Copy } from "lucide-react";
import Link from "next/link";

import { ActionForm } from "@/components/action-form";
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
import { formatDateTime, formatXOF, PAYMENT_STATUS, statusOf } from "@/lib/format";
import { refundDuplicate, verifyPayment } from "./actions";

export const metadata = { title: "Paiements" };

const LIMIT = 25;
const TABS = [
  { value: "", label: "Tous", query: "" },
  { value: "pending", label: "En attente", query: "status=pending" },
  { value: "duplicates", label: "Doublons", query: "duplicates=true" },
  { value: "failed", label: "Échoués", query: "status=failed" },
  { value: "refund_pending", label: "Remboursement en cours", query: "status=refund_pending" },
  { value: "refunded", label: "Remboursés", query: "status=refunded" },
];

type Props = { searchParams: Promise<{ status?: string; duplicates?: string; offset?: string }> };

export default async function PaymentsPage({ searchParams }: Props) {
  const sp = await searchParams;
  const duplicates = sp.duplicates === "true";
  const status = duplicates ? "" : (sp.status ?? "");
  const current = duplicates ? "duplicates" : status;
  const offset = Number(sp.offset ?? 0) || 0;

  let page: { items: Schemas["AdminPayment"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/payments", {
      query: { status, duplicates: duplicates || undefined, limit: LIMIT, offset },
    });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Argent"
        title="Suivi des paiements Mobile Money"
        highlight="paiements"
        description="Un paiement en attente est revérifié automatiquement ; vous pouvez forcer une revérification. Un paiement reçu en double se rembourse ici."
      />
      <FilterTabs
        current={current}
        tabs={TABS.map((t) => ({
          value: t.value,
          label: t.label,
          href: t.query ? `/payments?${t.query}` : "/payments",
        }))}
      />
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucun paiement dans cette liste." />
      ) : (
        <Table head={["Commande", "Opérateur", "Numéro", "Montant", "Statut", "Date", "Actions"]}>
          {page.items.map((p) => (
            <tr key={p.id}>
              <Td>
                <Link href={`/orders/${p.order_id}`} className="font-semibold text-secondary hover:underline">
                  Voir la commande
                </Link>
                <p className="font-mono text-[12px] text-text-muted">{p.reference}</p>
              </Td>
              <Td>{p.operator === "flooz" ? "Flooz" : "T-Money"}</Td>
              <Td>{p.phone_masked}</Td>
              <Td className="font-semibold">{formatXOF(p.amount_xof)}</Td>
              <Td>
                <div className="flex flex-col items-start gap-1">
                  <StatusBadge {...statusOf(PAYMENT_STATUS, p.status)} />
                  {p.is_duplicate && (
                    <span className="inline-flex items-center gap-1 text-[12px] font-semibold text-warning">
                      <Copy size={13} aria-hidden="true" /> En double
                    </span>
                  )}
                  {p.failure_reason && (
                    <span className="text-[12px] text-text-muted">{p.failure_reason}</span>
                  )}
                </div>
              </Td>
              <Td>{formatDateTime(p.created_at)}</Td>
              <Td>
                {p.status === "pending" && (
                  <ActionForm
                    action={verifyPayment}
                    label="Revérifier"
                    variant="outline"
                    hidden={{ id: p.id }}
                  />
                )}
                {p.is_duplicate && p.status === "succeeded" && (
                  <ActionForm
                    action={refundDuplicate}
                    label={`Rembourser ${formatXOF(p.amount_xof)}`}
                    hidden={{ id: p.id }}
                    confirm={{
                      title: `Rembourser ce doublon de ${formatXOF(p.amount_xof)} ?`,
                      body: `Transfert Mobile Money vers ${p.phone_masked}. Le paiement principal de la commande n'est pas touché.`,
                    }}
                    reason={{ label: "Motif (journal)" }}
                  />
                )}
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/payments"
        params={duplicates ? { duplicates: "true" } : { status }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
