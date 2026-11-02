import { ChevronLeft, Eye, ReceiptText } from "lucide-react";
import Link from "next/link";

import { ActionForm } from "@/components/action-form";
import {
  Card,
  CardTitle,
  EmptyState,
  ErrorState,
  Field,
  fieldClass,
  PageHeader,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, formatXOF, frDate, lomeDate } from "@/lib/format";
import { createSettlement } from "../actions";

export const metadata = { title: "Nouveau relevé" };

type Props = { searchParams: Promise<{ shop_id?: string; from?: string; to?: string }> };

/** Période proposée : du 1er du mois en cours à aujourd'hui (heure de Lomé). */
function defaultPeriod(): { from: string; to: string } {
  const today = lomeDate(new Date());
  return { from: today.slice(0, 8) + "01", to: today };
}

export default async function NewSettlementPage({ searchParams }: Props) {
  const sp = await searchParams;
  const period = defaultPeriod();
  const shopId = sp.shop_id ?? "";
  const from = sp.from ?? period.from;
  const to = sp.to ?? period.to;

  let shops: Schemas["Shop"][];
  let preview: Schemas["Settlement"] | null = null;
  try {
    shops = (
      await api<{ items: Schemas["Shop"][] }>("/v1/admin/shops", {
        query: { status: "published", limit: 100 },
      })
    ).items;
    if (shopId) {
      preview = await api<Schemas["Settlement"]>("/v1/admin/settlements/preview", {
        query: { shop_id: shopId, from, to },
      });
    }
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const lines = preview?.lines ?? [];

  return (
    <>
      <Link
        href="/settlements"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Relevés
      </Link>
      <PageHeader
        overline="Argent"
        title="Préparer un relevé"
        highlight="relevé"
        description="Choisissez la boutique et la période (dates de Lomé, bornes incluses). Les commandes déjà comprises dans un relevé sont exclues."
      />

      <Card className="mb-6">
        <form action="/settlements/new" className="grid grid-cols-[2fr_1fr_1fr_auto] items-end gap-3">
          <Field label="Boutique">
            <select name="shop_id" defaultValue={shopId} required className={fieldClass}>
              <option value="" disabled>
                Choisir une boutique publiée…
              </option>
              {shops.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                  {s.neighborhood_name && ` · ${s.neighborhood_name}`}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Du">
            <input type="date" name="from" defaultValue={from} required className={fieldClass} />
          </Field>
          <Field label="Au">
            <input type="date" name="to" defaultValue={to} required className={fieldClass} />
          </Field>
          <button className="inline-flex h-11 items-center gap-2 rounded-full bg-tertiary px-6 text-[15px] font-bold text-white hover:bg-[#163c6b]">
            <Eye size={17} aria-hidden="true" /> Aperçu
          </button>
        </form>
      </Card>

      {preview &&
        (lines.length === 0 ? (
          <EmptyState
            title="Aucune commande à reverser"
            message="Pas de commande remise et non encore relevée pour cette boutique sur la période."
          />
        ) : (
          <>
            <div className="mb-4 grid grid-cols-4 gap-2">
              <Total label="Commandes" value={String(preview.orders_count)} corner="tl" />
              <Total label="Produits encaissés" value={formatXOF(preview.gross_xof)} />
              <Total label="Commission ivia" value={formatXOF(preview.commission_xof)} />
              <Total label="Net à reverser" value={formatXOF(preview.net_xof)} corner="tr" strong />
            </div>
            <Table head={["Commande", "Remise le", "Produits", "Commission", "Net"]}>
              {lines.map((l) => (
                <tr key={l.order_id}>
                  <Td>
                    <Link
                      href={`/orders/${l.order_id}`}
                      className="font-semibold text-secondary hover:underline"
                    >
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
            <Card className="mt-4">
              <CardTitle icon={<ReceiptText size={18} aria-hidden="true" />}>Créer le relevé</CardTitle>
              <p className="mb-4 text-text-secondary">
                Ces {preview.orders_count} commandes seront rattachées au relevé et ne pourront plus figurer
                dans un autre. Le reversement se marque ensuite sur la fiche du relevé.
              </p>
              <ActionForm
                action={createSettlement}
                label={`Créer le relevé de ${formatXOF(preview.net_xof)}`}
                variant="imperial"
                hidden={{ shop_id: shopId, from, to }}
                confirm={{
                  title: `Créer le relevé du ${frDate(from)} au ${frDate(to)} ?`,
                  body: `${preview.orders_count} commande(s), ${formatXOF(preview.net_xof)} net à reverser au marchand.`,
                }}
                reason={{ label: "Note (facultative)" }}
              />
            </Card>
          </>
        ))}
    </>
  );
}

function Total({
  label,
  value,
  corner,
  strong,
}: {
  label: string;
  value: string;
  corner?: "tl" | "tr";
  strong?: boolean;
}) {
  const radius = corner === "tl" ? "rounded-tl-[18px]" : corner === "tr" ? "rounded-tr-[18px]" : "";
  return (
    <div className={`rounded-tile p-5 ${radius} ${strong ? "bg-tertiary text-white" : "bg-surface"}`}>
      <p className={`text-[13px] ${strong ? "text-white/75" : "text-text-muted"}`}>{label}</p>
      <p className="mt-1 text-[24px] font-bold leading-7 tracking-[-0.02em]">{value}</p>
    </div>
  );
}
