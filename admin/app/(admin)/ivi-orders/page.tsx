import { Bike, Clock3, Package, Store } from "lucide-react";
import Link from "next/link";

import { ActionForm } from "@/components/action-form";
import { LiveRefresh } from "@/components/live";
import { ServerForm } from "@/components/server-form";
import { EmptyState, ErrorState, fieldClass, FilterTabs, PageHeader, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, formatXOF, ORDER_STATUS, statusOf } from "@/lib/format";
import { orderAction } from "./actions";

export const metadata = { title: "Commandes IVI" };
export const dynamic = "force-dynamic";

type Order = Schemas["SellerOrder"];
type Props = { searchParams: Promise<{ group?: string }> };

const GROUPS = [
  { value: "new", label: "À accepter", href: "/ivi-orders" },
  { value: "active", label: "En cours", href: "/ivi-orders?group=active" },
  { value: "done", label: "Terminées", href: "/ivi-orders?group=done" },
];

const time = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Africa/Lome",
  hour: "2-digit",
  minute: "2-digit",
});

/** Boutons de l'étape suivante, comme dans Ivia Business. */
function Actions({ o }: { o: Order }) {
  const hidden = (action: string) => ({ id: o.id, action });
  switch (o.status) {
    case "awaiting_seller":
      return (
        <div className="flex flex-wrap gap-2">
          <ActionForm action={orderAction} label="Accepter" variant="imperial" hidden={hidden("accept")} />
          <ActionForm
            action={orderAction}
            label="Refuser"
            variant="outline"
            hidden={hidden("reject")}
            confirm={{ title: "Refuser la commande ?", body: "Le client sera remboursé intégralement." }}
            reason={{ label: "Motif (montré au client)", required: true }}
          />
        </div>
      );
    case "accepted":
      return (
        <ActionForm action={orderAction} label="Commencer la préparation" hidden={hidden("preparing")} />
      );
    case "preparing":
      return (
        <ActionForm action={orderAction} label="Commande prête" variant="imperial" hidden={hidden("ready")} />
      );
    case "ready_for_pickup":
      return (
        <ServerForm action={orderAction} submitLabel="Remettre" inline>
          <input type="hidden" name="id" value={o.id} />
          <input type="hidden" name="action" value="handover" />
          <label className="block">
            <span className="mb-1 block text-[12px] font-semibold text-text-secondary">Code du client</span>
            <input name="code" inputMode="numeric" required maxLength={8} className={`${fieldClass} w-36`} />
          </label>
        </ServerForm>
      );
    case "delivery_failed":
      return (
        <ActionForm action={orderAction} label="Confirmer le retour" hidden={hidden("confirm-return")} />
      );
    default:
      return null;
  }
}

export default async function IviOrdersPage({ searchParams }: Props) {
  const sp = await searchParams;
  const group = GROUPS.some((g) => g.value === sp.group) ? sp.group! : "new";
  let items: Order[];
  try {
    items = (await api<{ items: Order[] }>("/v1/admin/platform-orders", { query: { group, limit: 50 } }))
      .items;
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const generatedAt = new Date().toISOString();

  return (
    <>
      <PageHeader
        overline="Boutique IVI"
        title="Commandes IVI"
        highlight="IVI"
        description="Les commandes des produits IVI arrivent ici : le back-office joue le rôle du marchand."
        actions={
          <span className="text-[13px] text-text-secondary">
            <LiveRefresh seconds={15} generatedAt={generatedAt} />
          </span>
        }
      />
      <FilterTabs tabs={GROUPS} current={group} />

      {items.length === 0 ? (
        <EmptyState
          title={group === "new" ? "Aucune commande à accepter" : "Aucune commande"}
          message="Les commandes payées des produits IVI s'afficheront ici, avec une notification."
        />
      ) : (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2 2xl:grid-cols-3">
          {items.map((o, i) => {
            const st = statusOf(ORDER_STATUS, o.status);
            const late = o.status === "awaiting_seller" && o.seller_deadline_at;
            return (
              <section
                key={o.id}
                className="card-soft flex flex-col gap-4 rounded-field bg-surface p-5"
                style={{ animationDelay: `${Math.min(i, 8) * 50}ms` }}
              >
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <Link href={`/orders/${o.id}`} className="text-[17px] font-extrabold hover:text-primary">
                      {o.reference}
                    </Link>
                    <p className="text-[13px] text-text-muted">
                      {o.buyer_first_name || "Client"} · {formatDateTime(o.created_at)}
                    </p>
                  </div>
                  <StatusBadge label={st.label} tone={st.tone} />
                </div>

                <div className="flex flex-wrap gap-2 text-[12px] font-semibold">
                  <span className="inline-flex items-center gap-1.5 rounded-full bg-background px-2.5 py-1">
                    {o.fulfillment === "delivery" ? <Bike size={14} /> : <Store size={14} />}
                    {o.fulfillment === "delivery" ? "Livraison par un livreur ivia" : "Retrait en boutique"}
                  </span>
                  {late && (
                    <span className="inline-flex items-center gap-1.5 rounded-full bg-primary-soft px-2.5 py-1 text-primary-strong">
                      <Clock3 size={14} /> À accepter avant {time.format(new Date(o.seller_deadline_at!))}
                    </span>
                  )}
                </div>

                <ul className="space-y-1.5 text-[14px]">
                  {(o.items ?? []).map((it) => (
                    <li key={it.product_id} className="flex justify-between gap-3">
                      <span className="flex min-w-0 items-center gap-2">
                        <Package size={14} className="shrink-0 text-text-muted" />
                        <span className="truncate">
                          {it.quantity} × {it.product_name}
                        </span>
                      </span>
                      <span className="tabular-nums text-text-secondary">{formatXOF(it.line_total_xof)}</span>
                    </li>
                  ))}
                </ul>

                <div className="mt-auto flex items-end justify-between gap-3 border-t border-border pt-3">
                  <div className="text-[13px]">
                    <p className="text-text-muted">Produits</p>
                    <p className="text-[17px] font-extrabold">{formatXOF(o.subtotal_xof)}</p>
                  </div>
                  <Actions o={o} />
                </div>
              </section>
            );
          })}
        </div>
      )}
    </>
  );
}
