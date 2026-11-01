import {
  Banknote,
  Clock3,
  PackageCheck,
  Percent,
  ShoppingBag,
  Store,
  Timer,
  Truck,
  Wallet,
} from "lucide-react";

import { MosaicTile } from "@/components/illustration";
import { Card, CardTitle, ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatXOF } from "@/lib/format";

export const metadata = { title: "Tableau de bord" };

type Page<T> = { items: T[]; next_offset: number | null };

async function pendingCount(path: string, query: Record<string, string>): Promise<string> {
  const page = await api<Page<unknown>>(path, { query: { ...query, limit: 100 } });
  return page.next_offset !== null ? "100+" : String(page.items.length);
}

const frDate = (iso: string) => iso.split("-").reverse().join("/");

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
  const perDay = o.paid_per_day;
  const max = Math.max(1, ...perDay.map((p) => p.count));

  return (
    <>
      <PageHeader
        overline={`Du ${frDate(data.from)} au ${frDate(data.to)} · heure de Lomé`}
        title="Ce qui se passe sur la plateforme"
        highlight="la plateforme"
      />

      {/* Mosaïque « à traiter » : tuiles séparées de 8 px, coin extérieur arrondi à 18 px */}
      <section aria-labelledby="todo" className="mb-8">
        <h2 id="todo" className="mb-3 text-[12px] font-semibold uppercase tracking-[0.08em] text-text-muted">
          À traiter
        </h2>
        <div className="grid grid-cols-4 gap-2">
          <MosaicTile
            tone="imperial"
            cornerAt="tl"
            caption="Boutiques à valider"
            value={todo.shops}
            detail="Invisibles des acheteurs tant qu'elles ne sont pas publiées"
            href="/shops?status=pending_review"
            icon={<Store size={20} aria-hidden="true" />}
          />
          <MosaicTile
            tone="cobalt"
            caption="Livreurs à valider"
            value={todo.drivers}
            detail="Pièce d'identité et permis à vérifier"
            href="/drivers?review_status=pending_review"
            icon={<Truck size={20} aria-hidden="true" />}
          />
          <MosaicTile
            tone="berkeley"
            caption="Remboursements en attente"
            value={todo.refunds}
            detail="Commandes annulées après paiement"
            href="/refunds"
            icon={<Banknote size={20} aria-hidden="true" />}
          />
          <MosaicTile
            tone={todo.alerts > 0 ? "cornell" : "soft"}
            cornerAt="tr"
            caption="Commandes sans livreur"
            value={String(todo.alerts)}
            detail={todo.alerts > 0 ? "Aucun livreur n'a accepté à temps" : "Aucune alerte d'attribution"}
            href="/orders?status=awaiting_driver"
            icon={<Clock3 size={20} aria-hidden="true" />}
          />
        </div>
      </section>

      <div className="grid grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)] gap-4">
        <Card>
          <CardTitle
            icon={<ShoppingBag size={18} aria-hidden="true" />}
            aside={<span className="text-[13px] text-text-muted">par jour</span>}
          >
            Commandes payées
          </CardTitle>
          <p className="text-[40px] font-bold leading-[44px] tracking-[-0.02em]">{o.paid_orders}</p>
          {perDay.length === 0 ? (
            <p className="mt-6 text-text-secondary">Pas encore de commande payée sur la période.</p>
          ) : (
            <ol className="mt-6 flex h-32 items-end gap-1.5" aria-label="Commandes payées par jour">
              {perDay.map((p) => (
                <li
                  key={p.day}
                  className="flex h-full flex-1 flex-col justify-end"
                  title={`${frDate(p.day)} : ${p.count}`}
                >
                  <span
                    className="block w-full rounded-t-[6px] bg-tertiary"
                    style={{ height: `${Math.max(4, (p.count / max) * 100)}%` }}
                  />
                </li>
              ))}
            </ol>
          )}
        </Card>

        <Card>
          <CardTitle icon={<Wallet size={18} aria-hidden="true" />}>Argent</CardTitle>
          <Metric label="Volume des commandes remises" value={formatXOF(o.gmv_xof)} />
          <Metric label="Commission de la plateforme" value={formatXOF(o.commission_xof)} highlight />
        </Card>
      </div>

      <div className="mt-4 grid grid-cols-4 gap-4">
        <Stat
          icon={<PackageCheck size={18} />}
          label="Commandes remises"
          value={String(o.completed_orders)}
        />
        <Stat
          icon={<Percent size={18} />}
          label="Annulées après paiement"
          value={`${o.cancellation_rate_pct.toFixed(1)} %`}
        />
        <Stat
          icon={<Timer size={18} />}
          label="Prête → livrée (médiane)"
          value={`${Math.round(o.median_ready_to_delivered_minutes)} min`}
        />
        <Stat
          icon={<Truck size={18} />}
          label="Livreur trouvé en moins de 10 min"
          value={`${data.delivery.assigned_within_10_min_pct.toFixed(0)} %`}
        />
      </div>

      {data.payments_pending_over_15_min > 0 && (
        <p
          role="status"
          className="mt-4 flex items-center gap-2 rounded-field bg-[#FBEFE3] px-5 py-3 text-warning"
        >
          <Clock3 size={16} aria-hidden="true" />
          {data.payments_pending_over_15_min} paiement(s) en attente depuis plus de 15 minutes : la
          revérification automatique est en cours.
        </p>
      )}
    </>
  );
}

function Metric({ label, value, highlight }: { label: string; value: string; highlight?: boolean }) {
  return (
    <div className="border-b border-border py-4 first:pt-0 last:border-0 last:pb-0">
      <p className="text-[13px] text-text-muted">{label}</p>
      <p
        className={`mt-1 text-[28px] font-bold leading-8 tracking-[-0.02em] ${highlight ? "text-primary-strong" : ""}`}
      >
        {value}
      </p>
    </div>
  );
}

function Stat({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <Card className="p-5">
      <span
        aria-hidden="true"
        className="mb-4 grid size-9 place-items-center rounded-card bg-secondary-soft text-tertiary"
      >
        {icon}
      </span>
      <p className="text-[22px] font-bold leading-7">{value}</p>
      <p className="mt-1 text-[13px] text-text-muted">{label}</p>
    </Card>
  );
}
