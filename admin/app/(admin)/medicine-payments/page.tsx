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
import { formatDateTime, formatXOF, MEDICINE_PAYMENT_STATUS, statusOf } from "@/lib/format";
import { refundMedicinePayment } from "../pharmacies/actions";

export const metadata = { title: "Paiements santé" };

const LIMIT = 20;
const TABS = [
  { value: "", label: "Tous" },
  { value: "succeeded", label: "Réussis" },
  { value: "pending", label: "En attente" },
  { value: "failed", label: "Échoués" },
  { value: "refund_pending", label: "Remboursement en cours" },
  { value: "refunded", label: "Remboursés" },
];

export default async function MedicinePaymentsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; offset?: string }>;
}) {
  const sp = await searchParams;
  const status = sp.status || undefined;
  const offset = Number(sp.offset ?? 0) || 0;
  let page: { items: Schemas["MedicinePayment"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/medicine-payments", { query: { status, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Santé"
        title="Les paiements santé"
        highlight="paiements"
        description="Déblocages de pharmacies et commandes livrées, payés en Mobile Money."
      />
      <FilterTabs
        current={status ?? ""}
        tabs={TABS.map((t) => ({
          value: t.value,
          label: t.label,
          href: t.value ? `/medicine-payments?status=${t.value}` : "/medicine-payments",
        }))}
      />
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucun paiement dans cette liste pour le moment." />
      ) : (
        <Table head={["Objet", "Montant", "Moyen", "Statut", "Date", ""]}>
          {page.items.map((p) => (
            <tr key={p.id}>
              <Td>
                <Link
                  href={`/medicine-alerts/${p.alert_id}`}
                  className="font-semibold text-secondary hover:underline"
                >
                  {p.purpose === "unlock" ? "Déblocage" : "Commande"}
                </Link>
              </Td>
              <Td>{formatXOF(p.amount_xof)}</Td>
              <Td>
                {p.operator === "flooz" ? "Flooz" : "T-Money"} · {p.phone_masked}
              </Td>
              <Td>
                <StatusBadge {...statusOf(MEDICINE_PAYMENT_STATUS, p.status)} />
              </Td>
              <Td>{formatDateTime(p.created_at)}</Td>
              <Td>
                {p.status === "succeeded" && (
                  <ActionForm
                    action={refundMedicinePayment}
                    label="Rembourser"
                    variant="outline"
                    hidden={{ id: p.id }}
                    confirm={{
                      title: `Rembourser ${formatXOF(p.amount_xof)} ?`,
                      body: "Le patient est remboursé sur son Mobile Money. L'action est journalisée.",
                    }}
                    reason={{ label: "Motif du remboursement", required: true }}
                  />
                )}
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/medicine-payments"
        params={{ status }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
