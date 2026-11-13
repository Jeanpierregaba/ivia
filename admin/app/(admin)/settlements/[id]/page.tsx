import { BadgeCheck, ChevronLeft, ReceiptText } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ActionForm } from "@/components/action-form";
import { ServerForm } from "@/components/server-form";
import {
  Card,
  CardTitle,
  DefinitionList,
  ErrorState,
  Field,
  fieldClass,
  StatusBadge,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, formatXOF, frDate, SETTLEMENT_STATUS, statusOf } from "@/lib/format";
import { deleteSettlement, markSettled } from "../actions";

export const metadata = { title: "Relevé marchand" };

export default async function SettlementPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  let s: Schemas["Settlement"];
  try {
    s = await api<Schemas["Settlement"]>(`/v1/admin/settlements/${encodeURIComponent(id)}`);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const open = s.status === "open";

  return (
    <>
      <Link
        href="/settlements"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Relevés
      </Link>
      <header className="mb-6 flex items-center gap-6 rounded-field bg-tertiary p-6 text-white">
        <div className="min-w-0 flex-1">
          <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-white/60">
            Relevé marchand
          </p>
          <h1 className="text-[28px] font-bold leading-8 tracking-[-0.02em]">{s.shop_name || "Boutique"}</h1>
          <p className="mt-1 text-white/75">
            Du {frDate(s.period_start)} au {frDate(s.period_end)} · {s.orders_count} commande(s)
          </p>
        </div>
        <div className="text-right">
          <p className="text-[13px] text-white/60">Net à reverser</p>
          <p className="text-[28px] font-bold leading-8">{formatXOF(s.net_xof)}</p>
        </div>
        <span className="rounded-full bg-surface">
          <StatusBadge {...statusOf(SETTLEMENT_STATUS, s.status)} />
        </span>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)] gap-4">
        <Card>
          <CardTitle icon={<ReceiptText size={18} aria-hidden="true" />}>Montants</CardTitle>
          <DefinitionList
            items={[
              ["Produits encaissés", formatXOF(s.gross_xof)],
              ["Commission ivia", formatXOF(s.commission_xof)],
              ["Net à reverser", <strong key="n">{formatXOF(s.net_xof)}</strong>],
              ["Créé le", formatDateTime(s.created_at)],
              ["Réglé le", formatDateTime(s.settled_at)],
              ["Référence du virement", s.settlement_reference || "—"],
              ["Note", s.note || "—"],
            ]}
          />
        </Card>

        {open ? (
          <Card>
            <CardTitle icon={<BadgeCheck size={18} aria-hidden="true" />}>Marquer comme réglé</CardTitle>
            <ServerForm action={markSettled} submitLabel="Marquer comme réglé" variant="imperial">
              <input type="hidden" name="id" value={id} />
              <Field
                label="Référence du virement"
                hint="Identifiant de la transaction Mobile Money ou bancaire."
              >
                <input name="settlement_reference" required maxLength={100} className={fieldClass} />
              </Field>
              <Field label="Note (facultative)">
                <input name="note" maxLength={500} className={fieldClass} />
              </Field>
            </ServerForm>
            <div className="mt-6 border-t border-border pt-5">
              <ActionForm
                action={deleteSettlement}
                label="Supprimer ce relevé"
                variant="outline"
                hidden={{ id }}
                confirm={{
                  title: "Supprimer ce relevé ?",
                  body: "Ses commandes redeviennent disponibles pour un nouveau relevé. Rien n'a été versé.",
                }}
                reason={{ label: "Motif", required: true }}
              />
            </div>
          </Card>
        ) : (
          <Card>
            <CardTitle icon={<BadgeCheck size={18} aria-hidden="true" />}>Reversement effectué</CardTitle>
            <p className="text-text-secondary">
              Réglé le {formatDateTime(s.settled_at)}, référence <strong>{s.settlement_reference}</strong>. Un
              relevé réglé n&apos;est plus modifiable.
            </p>
          </Card>
        )}
      </div>

      <h2 className="mb-3 mt-8 text-[17px] font-bold">Commandes du relevé</h2>
      <Table head={["Commande", "Remise le", "Produits", "Commission", "Net"]}>
        {(s.lines ?? []).map((l) => (
          <tr key={l.order_id}>
            <Td>
              <Link href={`/orders/${l.order_id}`} className="font-semibold text-secondary hover:underline">
                {l.order_reference}
              </Link>
            </Td>
            <Td>{formatDateTime(l.completed_at)}</Td>
            <Td>{formatXOF(l.subtotal_xof)}</Td>
            <Td>{formatXOF(l.commission_xof)}</Td>
            <Td className="font-semibold">{formatXOF(l.net_xof)}</Td>
          </tr>
        ))}
      </Table>
    </>
  );
}
