import Link from "next/link";
import { notFound } from "next/navigation";

import { ActionForm } from "@/components/action-form";
import { Card, DefinitionList, ErrorState, PageHeader, StatusBadge, Table, Td } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, formatXOF, ORDER_STATUS, statusOf, VEHICLE } from "@/lib/format";
import { orderAction } from "../actions";

export const metadata = { title: "Commande" };

const ADMIN_CANCELLABLE = ["awaiting_seller", "accepted", "preparing", "ready_for_pickup", "awaiting_driver"];

export default async function OrderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  let o: Schemas["AdminOrder"];
  let payments: { items: Schemas["AdminPayment"][] };
  try {
    [o, payments] = await Promise.all([
      api<Schemas["AdminOrder"]>(`/v1/admin/orders/${encodeURIComponent(id)}`),
      api<{ items: Schemas["AdminPayment"][] }>("/v1/admin/payments", { query: { order_id: id, limit: 20 } }),
    ]);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const hidden = (action: string) => ({ id: o.id, action });
  const refundable = (o.status === "cancelled" || o.status === "returned_to_shop") && o.refund_due_xof > 0;

  return (
    <>
      <Link href="/orders" className="mb-2 inline-block text-sm font-semibold text-secondary hover:underline">
        ← Commandes
      </Link>
      <PageHeader
        title={`Commande ${o.reference}`}
        actions={<StatusBadge {...statusOf(ORDER_STATUS, o.status)} />}
      />

      <div className="grid grid-cols-2 gap-4">
        <Card>
          <h2 className="mb-4 text-[17px] font-bold">Détail</h2>
          <DefinitionList
            items={[
              [
                "Mode",
                o.fulfillment === "delivery"
                  ? `Livraison (${VEHICLE[o.vehicle_type ?? ""] ?? "—"})`
                  : "Retrait en boutique",
              ],
              ["Produits", formatXOF(o.subtotal_xof)],
              ["Livraison", formatXOF(o.delivery_fee_xof)],
              ["Total payé", <strong key="t">{formatXOF(o.total_xof)}</strong>],
              ["Commission", formatXOF(o.commission_xof)],
              ["À rembourser", o.refund_due_xof > 0 ? formatXOF(o.refund_due_xof) : "—"],
              ["Essais de code", `${o.handover_attempts} / 5`],
              ["Motif d'annulation", o.cancel_reason || "—"],
            ]}
          />
        </Card>
        <Card>
          <h2 className="mb-4 text-[17px] font-bold">Historique</h2>
          <ol className="space-y-2">
            {o.events.map((e, i) => (
              <li key={i} className="flex justify-between gap-4">
                <span>
                  {statusOf(ORDER_STATUS, e.to_status).label}
                  {e.reason && <span className="block text-[13px] text-text-muted">{e.reason}</span>}
                </span>
                <span className="shrink-0 text-[13px] text-text-muted">{formatDateTime(e.created_at)}</span>
              </li>
            ))}
          </ol>
        </Card>
      </div>

      <h2 className="mb-3 mt-6 text-[17px] font-bold">Produits</h2>
      <Table head={["Produit", "Prix unitaire", "Quantité", "Total"]}>
        {o.items.map((it) => (
          <tr key={it.product_id}>
            <Td>{it.product_name}</Td>
            <Td>{formatXOF(it.unit_price_xof)}</Td>
            <Td>{it.quantity}</Td>
            <Td>{formatXOF(it.line_total_xof)}</Td>
          </tr>
        ))}
      </Table>

      <h2 className="mb-3 mt-6 text-[17px] font-bold">Paiements</h2>
      {payments.items.length === 0 ? (
        <p className="text-text-secondary">Aucun paiement.</p>
      ) : (
        <Table head={["Opérateur", "Numéro", "Montant", "Statut", "Date"]}>
          {payments.items.map((p) => (
            <tr key={p.id}>
              <Td>{p.operator === "flooz" ? "Flooz" : "T-Money"}</Td>
              <Td>{p.phone_masked}</Td>
              <Td>{formatXOF(p.amount_xof)}</Td>
              <Td>
                {p.status}
                {p.is_duplicate && " (en double)"}
              </Td>
              <Td>{formatDateTime(p.created_at)}</Td>
            </tr>
          ))}
        </Table>
      )}

      <Card className="mt-6">
        <h2 className="mb-4 text-[17px] font-bold">Actions</h2>
        <div className="flex flex-wrap gap-3">
          {refundable && (
            <ActionForm
              action={orderAction}
              label={`Rembourser ${formatXOF(o.refund_due_xof)}`}
              hidden={hidden("refund")}
              confirm={{
                title: `Rembourser ${formatXOF(o.refund_due_xof)} ?`,
                body: `Transfert Mobile Money vers le numéro qui a payé la commande ${o.reference}.`,
              }}
              reason={{ label: "Motif (journal)" }}
            />
          )}
          {ADMIN_CANCELLABLE.includes(o.status) && (
            <ActionForm
              action={orderAction}
              label="Annuler la commande"
              variant="danger"
              hidden={hidden("cancel")}
              confirm={{
                title: `Annuler la commande ${o.reference} ?`,
                body: `Le stock est rendu. Montant payé : ${formatXOF(o.total_xof)}, à rembourser ensuite.`,
              }}
              reason={{ label: "Motif de l'annulation", required: true }}
            />
          )}
          {o.status === "driver_assigned" && (
            <ActionForm
              action={orderAction}
              label="Retirer le livreur"
              variant="outline"
              hidden={hidden("unassign-driver")}
              confirm={{
                title: "Retirer le livreur ?",
                body: "La recherche d'un autre livreur reprend aussitôt.",
              }}
              reason={{ label: "Motif", required: true }}
            />
          )}
          {o.status === "delivery_failed" && (
            <ActionForm
              action={orderAction}
              label="Confirmer le retour en boutique"
              variant="outline"
              hidden={hidden("confirm-return")}
              confirm={{
                title: "Confirmer le retour du colis ?",
                body: `Le livreur est libéré ; ${formatXOF(o.subtotal_xof)} (produits) seront à rembourser.`,
              }}
              reason={{ label: "Comment le retour a-t-il été vérifié ?", required: true }}
            />
          )}
          {o.handover_attempts >= 5 && (
            <ActionForm
              action={orderAction}
              label="Débloquer le code de remise"
              variant="outline"
              hidden={hidden("unlock-handover")}
              confirm={{
                title: "Débloquer le code ?",
                body: "À faire seulement après avoir vérifié l'identité de l'acheteur.",
              }}
              reason={{ label: "Vérification effectuée", required: true }}
            />
          )}
        </div>
      </Card>
    </>
  );
}
