import { ChevronLeft, CreditCard, History, Receipt, ShoppingBasket, Wrench } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ActionForm } from "@/components/action-form";
import { Card, CardTitle, DefinitionList, ErrorState, StatusBadge, Table, Td } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, formatXOF, ORDER_STATUS, PAYMENT_STATUS, statusOf, VEHICLE } from "@/lib/format";
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
      <Link
        href="/orders"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Commandes
      </Link>
      <header className="mb-6 flex items-center gap-6 rounded-field bg-tertiary p-6 text-white">
        <div className="min-w-0 flex-1">
          <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-white/60">
            Commande · {o.fulfillment === "delivery" ? "Livraison" : "Retrait en boutique"}
          </p>
          <h1 className="text-[24px] font-bold leading-8 tracking-[-0.02em]">{o.reference}</h1>
          <p className="mt-1 text-white/75">Créée le {formatDateTime(o.created_at)}</p>
        </div>
        <div className="text-right">
          <p className="text-[13px] text-white/60">Total payé</p>
          <p className="text-[24px] font-bold leading-8">{formatXOF(o.total_xof)}</p>
        </div>
        <span className="rounded-full bg-surface">
          <StatusBadge {...statusOf(ORDER_STATUS, o.status)} />
        </span>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardTitle icon={<Receipt size={18} aria-hidden="true" />}>Détail</CardTitle>
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
          <CardTitle icon={<History size={18} aria-hidden="true" />}>Historique</CardTitle>
          <ol className="relative space-y-4 border-l-2 border-border pl-5">
            {o.events.map((e, i) => (
              <li key={i} className="relative flex justify-between gap-4">
                <span
                  aria-hidden="true"
                  className={`absolute -left-[27px] top-1.5 size-3 rounded-full ring-4 ring-surface ${
                    i === o.events.length - 1 ? "bg-primary" : "bg-tertiary"
                  }`}
                />
                <span className="font-semibold">
                  {statusOf(ORDER_STATUS, e.to_status).label}
                  {e.reason && (
                    <span className="block text-[13px] font-normal text-text-muted">{e.reason}</span>
                  )}
                </span>
                <span className="shrink-0 text-[13px] text-text-muted">{formatDateTime(e.created_at)}</span>
              </li>
            ))}
          </ol>
        </Card>
      </div>

      <h2 className="mb-3 mt-8 flex items-center gap-2 text-[15px] font-bold">
        <ShoppingBasket size={18} aria-hidden="true" className="text-secondary" /> Produits
      </h2>
      <Table head={["Produit", "Prix unitaire", "Quantité", "Total"]}>
        {o.items.map((it) => (
          <tr key={it.product_id}>
            <Td>{it.product_name}</Td>
            <Td>{formatXOF(it.unit_price_xof)}</Td>
            <Td>{it.quantity}</Td>
            <Td className="font-semibold">{formatXOF(it.line_total_xof)}</Td>
          </tr>
        ))}
      </Table>

      <h2 className="mb-3 mt-8 flex items-center gap-2 text-[15px] font-bold">
        <CreditCard size={18} aria-hidden="true" className="text-secondary" /> Paiements
      </h2>
      {payments.items.length === 0 ? (
        <p className="rounded-field bg-surface px-5 py-4 text-text-secondary">
          Aucun paiement pour cette commande.
        </p>
      ) : (
        <Table head={["Opérateur", "Numéro", "Montant", "Statut", "Date"]}>
          {payments.items.map((p) => (
            <tr key={p.id}>
              <Td>{p.operator === "flooz" ? "Flooz" : "T-Money"}</Td>
              <Td>{p.phone_masked}</Td>
              <Td>{formatXOF(p.amount_xof)}</Td>
              <Td>
                <StatusBadge {...statusOf(PAYMENT_STATUS, p.status)} />
                {p.is_duplicate && <span className="ml-2 text-[13px] text-warning">en double</span>}
              </Td>
              <Td>{formatDateTime(p.created_at)}</Td>
            </tr>
          ))}
        </Table>
      )}

      <Card className="mt-8">
        <CardTitle icon={<Wrench size={18} aria-hidden="true" />}>Actions</CardTitle>
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
