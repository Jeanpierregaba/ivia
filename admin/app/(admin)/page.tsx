import Link from "next/link";

import { Card, ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatXOF } from "@/lib/format";

export const metadata = { title: "Tableau de bord" };

type Page<T> = { items: T[]; next_offset: number | null };

async function pendingCount(path: string, query: Record<string, string>): Promise<string> {
  const page = await api<Page<unknown>>(path, { query: { ...query, limit: 100 } });
  return page.next_offset !== null ? "100+" : String(page.items.length);
}

export default async function DashboardPage() {
  let data: Schemas["Dashboard"];
  let todo: { shops: string; drivers: string; refunds: string; alerts: number };
  try {
    const [d, shops, drivers, refunds, alerts] = await Promise.all([
      // Sans période, l'API retient les 30 derniers jours (heure de Lomé).
      api<Schemas["Dashboard"]>("/v1/admin/metrics"),
      pendingCount("/v1/admin/shops", { status: "pending_review" }),
      pendingCount("/v1/admin/drivers", { review_status: "pending_review" }),
      pendingCount("/v1/admin/refund-queue", {}),
      api<{ items: unknown[] }>("/v1/admin/delivery-alerts"),
    ]);
    data = d;
    todo = { shops, drivers, refunds, alerts: alerts.items.length };
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const o = data.orders;
  return (
    <>
      <PageHeader title="Tableau de bord" description="Les 30 derniers jours, heure de Lomé." />

      <h2 className="mb-3 text-[17px] font-bold">À traiter</h2>
      <div className="mb-8 grid grid-cols-4 gap-4">
        <Todo href="/shops?status=pending_review" label="Boutiques à valider" value={todo.shops} />
        <Todo href="/drivers?review_status=pending_review" label="Livreurs à valider" value={todo.drivers} />
        <Todo href="/refunds" label="Remboursements en attente" value={todo.refunds} />
        <Todo
          href="/orders?status=awaiting_driver"
          label="Commandes sans livreur (alertes)"
          value={String(todo.alerts)}
        />
      </div>

      <h2 className="mb-3 text-[17px] font-bold">Activité</h2>
      <div className="grid grid-cols-4 gap-4">
        <Stat label="Commandes payées" value={String(o.paid_orders)} />
        <Stat label="Commandes remises" value={String(o.completed_orders)} />
        <Stat label="Volume remis" value={formatXOF(o.gmv_xof)} />
        <Stat label="Commission" value={formatXOF(o.commission_xof)} />
        <Stat label="Taux d'annulation après paiement" value={`${o.cancellation_rate_pct.toFixed(1)} %`} />
        <Stat
          label="Délai médian prête → livrée"
          value={`${Math.round(o.median_ready_to_delivered_minutes)} min`}
        />
        <Stat
          label="Livreur trouvé en moins de 10 min"
          value={`${data.delivery.assigned_within_10_min_pct.toFixed(0)} %`}
        />
        <Stat label="Paiements en attente depuis 15 min" value={String(data.payments_pending_over_15_min)} />
      </div>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <Card className="p-5">
      <p className="text-[13px] text-text-muted">{label}</p>
      <p className="mt-1 text-[22px] font-semibold leading-7">{value}</p>
    </Card>
  );
}

function Todo({ href, label, value }: { href: string; label: string; value: string }) {
  return (
    <Link href={href} className="rounded-card bg-surface p-5 hover:outline-2 hover:outline-secondary">
      <p className="text-[13px] text-text-muted">{label}</p>
      <p className="mt-1 text-[28px] font-bold leading-8 text-tertiary">{value}</p>
    </Link>
  );
}
