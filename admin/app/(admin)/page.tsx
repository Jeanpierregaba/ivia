import { Bell, Search } from "lucide-react";
import Link from "next/link";

import { AnimatedNumber, LiveRefresh, PeriodMenu } from "@/components/live";
import { cx, ErrorState } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { ActiveOrders, AuditFeed, DriversPanel, PaidChart } from "./dashboard-parts";

export const metadata = { title: "Tableau de bord" };

type Overview = Schemas["AdminOverview"];
type Props = { searchParams: Promise<{ period?: string; group?: string }> };

const PERIODS = [
  { value: "today", label: "Aujourd'hui" },
  { value: "7d", label: "7 derniers jours" },
  { value: "30d", label: "30 derniers jours" },
];
const GROUPS = ["to_accept", "without_driver", "locked"];

const longDate = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Africa/Lome",
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
});
// Montants courts de la maquette : « 21 350 F ».
const grouped = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
const F = (n: number) => `${grouped.format(n)} F`;
const weekday = new Intl.DateTimeFormat("fr-FR", { timeZone: "Africa/Lome", weekday: "long" });

// Maquette B03 : tout le tableau de bord vient de GET /v1/admin/overview, relu toutes les 30 s.
export default async function DashboardPage({ searchParams }: Props) {
  const sp = await searchParams;
  const period = PERIODS.some((p) => p.value === sp.period) ? sp.period! : "today";
  const group = GROUPS.includes(sp.group ?? "") ? sp.group! : "";

  let o: Overview;
  let me: Schemas["User"];
  let unread = 0;
  try {
    const [overview, user, notifs] = await Promise.all([
      api<Overview>("/v1/admin/overview", { query: { period, group } }),
      api<Schemas["User"]>("/v1/me"),
      api<{ unread_count: number }>("/v1/notifications", { query: { app: "admin", limit: 1 } }),
    ]);
    o = overview;
    me = user;
    unread = notifs.unread_count;
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const now = new Date(o.generated_at);
  const today = longDate.format(now);
  const href = (p: string, g: string) => {
    const q = new URLSearchParams();
    if (p !== "today") q.set("period", p);
    if (g) q.set("group", g);
    const s = q.toString();
    return s ? `/?${s}` : "/";
  };
  const k = o.kpis;
  const delta =
    o.kpis.paid_orders_prev > 0
      ? Math.round(((k.paid_orders - k.paid_orders_prev) / k.paid_orders_prev) * 100)
      : null;
  const versus =
    period === "today"
      ? `vs ${weekday.format(new Date(now.getTime() - 7 * 86400_000))} dernier`
      : period === "7d"
        ? "vs 7 jours précédents"
        : "vs 30 jours précédents";

  return (
    <>
      <LiveRefreshHeader
        firstName={me.first_name || "à vous"}
        date={today.charAt(0).toUpperCase() + today.slice(1)}
        generatedAt={o.generated_at}
        period={period}
        periodOptions={PERIODS.map((p) => ({ ...p, href: href(p.value, group) }))}
        unread={unread}
      />

      {/* À traiter */}
      <h2 className="mb-3 text-[14px] font-extrabold uppercase tracking-[0.12em] text-text-secondary">
        À traiter
      </h2>
      <div className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
        <TodoCard
          tone="#ED1C2F"
          value={o.todo.refunds}
          action="Rembourser"
          title="Remboursements en attente"
          detail={
            o.todo.refunds
              ? `Commandes annulées après paiement · ${F(o.todo.refunds_xof)}`
              : "Aucun remboursement en attente"
          }
          href="/refunds"
          delay={0}
        />
        <TodoCard
          tone="#0E2E54"
          value={o.todo.shops}
          action="Examiner"
          title="Boutiques à valider"
          detail={
            o.todo.shops && o.todo.shops_oldest
              ? `La plus ancienne attend depuis ${ago(o.todo.shops_oldest, now)}`
              : "Aucune boutique en attente"
          }
          href="/shops?status=pending_review"
          delay={60}
        />
        <TodoCard
          tone="#004DA8"
          value={o.todo.drivers}
          action="Examiner"
          title="Livreurs à valider"
          detail={o.todo.drivers ? "Documents reçus, à vérifier" : "Aucun dossier en attente"}
          href="/drivers?review_status=pending_review"
          delay={120}
        />
        <TodoCard
          tone="#AA0E1B"
          value={o.todo.handover_locked}
          action="Intervenir"
          title="Code de remise bloqué"
          detail={
            o.todo.handover_locked_order
              ? `5 essais échoués · #${o.todo.handover_locked_order.number}`
              : "Aucun code bloqué"
          }
          href={o.todo.handover_locked_order ? `/orders/${o.todo.handover_locked_order.id}` : "/orders"}
          delay={180}
        />
        <TodoCard
          tone="#8A5A00"
          value={o.todo.unassigned}
          action="Assigner"
          title="Commande sans livreur"
          detail={
            o.todo.unassigned_order
              ? `${o.todo.unassigned_order.offers_count} livreur${o.todo.unassigned_order.offers_count > 1 ? "s ont" : " a"} refusé · #${o.todo.unassigned_order.number}`
              : "Toutes les commandes ont un livreur"
          }
          href={
            o.todo.unassigned_order
              ? `/orders/${o.todo.unassigned_order.id}`
              : "/orders?status=awaiting_driver"
          }
          delay={240}
        />
      </div>

      {/* Indicateurs */}
      <div className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
        <KpiCard label="Commandes payées">
          <BigValue>
            <AnimatedNumber value={k.paid_orders} />
          </BigValue>
          <p className="mt-3 text-[14px] text-text-muted">
            {delta === null ? "Pas de comparaison" : `${delta >= 0 ? "+" : ""}${delta} % ${versus}`}
          </p>
        </KpiCard>
        <KpiCard label="Volume des ventes">
          <BigValue>
            <AnimatedNumber value={k.gmv_xof} kind="xof" />
          </BigValue>
          <p className="mt-3 text-[14px] text-text-muted">Commission : {F(k.commission_xof)}</p>
        </KpiCard>
        <KpiCard label="Annulées ou remboursées">
          <BigValue>{pct(k.cancellation_rate_pct, 1)}</BigValue>
          <Goal note="Sur 30 jours" label="Objectif < 5 %" ok={k.cancellation_rate_pct < 5} />
        </KpiCard>
        <KpiCard label="Livreur assigné < 10 min">
          <BigValue>{pct(k.assigned_within_10_min_pct, 0)}</BigValue>
          <Goal note="Commandes prêtes" label="Objectif 80 %" ok={k.assigned_within_10_min_pct >= 80} />
        </KpiCard>
        <KpiCard label="Prête → livrée">
          <BigValue>
            {k.median_ready_to_delivered_minutes > 0
              ? `${Math.round(k.median_ready_to_delivered_minutes)} min`
              : "—"}
          </BigValue>
          <Goal
            note="Délai médian"
            label="Objectif < 45 min"
            ok={k.median_ready_to_delivered_minutes === 0 || k.median_ready_to_delivered_minutes < 45}
          />
        </KpiCard>
      </div>

      <div className="mb-4 grid grid-cols-[minmax(0,1.75fr)_minmax(0,1fr)] gap-4 max-[1200px]:grid-cols-1">
        <PaidChart days={o.paid_per_day} />
        <DriversPanel
          drivers={o.drivers}
          payments={o.payments}
          periodLabel={PERIODS.find((p) => p.value === period)!.label}
        />
      </div>

      <div className="grid grid-cols-[minmax(0,1.75fr)_minmax(0,1fr)] gap-4 max-[1200px]:grid-cols-1">
        <ActiveOrders active={o.active_orders} now={o.generated_at} chipHref={(g) => href(period, g)} />
        <AuditFeed lines={o.audit} now={o.generated_at} />
      </div>
    </>
  );
}

function LiveRefreshHeader(props: {
  firstName: string;
  date: string;
  generatedAt: string;
  period: string;
  periodOptions: { value: string; label: string; href: string }[];
  unread: number;
}) {
  return (
    <header className="animate-rise mb-7 flex flex-wrap items-start justify-between gap-6">
      <div>
        <h1 className="text-[32px] font-extrabold leading-[38px] tracking-[-0.03em] sm:text-[44px] sm:leading-[48px]">
          Bonjour {props.firstName}
        </h1>
        <p className="mt-2 text-[17px] text-text-secondary">
          {props.date} · Lomé · <LiveRefresh generatedAt={props.generatedAt} />
        </p>
      </div>
      <div className="flex w-full flex-wrap items-center gap-3 sm:w-auto">
        <form action="/search" role="search" className="relative min-w-0 flex-1 sm:flex-none">
          <Search
            size={19}
            aria-hidden="true"
            className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-text-muted"
          />
          <label htmlFor="global-search" className="sr-only">
            Rechercher une commande, une boutique, un livreur, un téléphone
          </label>
          <input
            id="global-search"
            name="q"
            placeholder="Commande, boutique, livreur, téléphone…"
            className="h-[54px] w-full rounded-[14px] bg-surface pl-12 pr-4 text-[15px] outline-none transition-shadow duration-300 focus:shadow-[inset_0_0_0_2px_var(--color-primary)] sm:w-[260px] 2xl:w-[380px]"
          />
        </form>
        <PeriodMenu current={props.period} options={props.periodOptions} />
        <Link
          href="/notifications"
          aria-label={props.unread ? `${props.unread} notification(s) non lue(s)` : "Notifications"}
          className="relative grid size-[54px] place-items-center rounded-[14px] bg-surface hover:bg-white/70"
        >
          <Bell size={21} aria-hidden="true" />
          {props.unread > 0 && (
            <span className="animate-live absolute right-3 top-3 size-2.5 rounded-full bg-primary ring-2 ring-surface" />
          )}
        </Link>
      </div>
    </header>
  );
}

function TodoCard(props: {
  tone: string;
  value: number;
  action: string;
  title: string;
  detail: string;
  href: string;
  delay: number;
}) {
  const idle = props.value === 0;
  return (
    <Link
      href={props.href}
      style={{ borderTopColor: props.tone, animationDelay: `${props.delay}ms` }}
      className="animate-rise group block rounded-[18px] border-t-[5px] bg-surface p-6 transition-transform hover:-translate-y-0.5 hover:shadow-[0_10px_24px_rgba(14,46,84,0.10)]"
    >
      <div className="flex items-start justify-between gap-3">
        <span
          className="text-[44px] font-extrabold leading-none"
          style={{ color: idle ? "#9AA5B4" : props.tone }}
        >
          <AnimatedNumber value={props.value} />
        </span>
        <span className="rounded-full bg-background px-3.5 py-1.5 text-[14px] font-bold transition-colors group-hover:bg-tertiary group-hover:text-white">
          {props.action}
        </span>
      </div>
      <p className="mt-5 text-[19px] font-extrabold leading-[24px]">{props.title}</p>
      <p className="mt-1.5 text-[14px] leading-[20px] text-text-muted">{props.detail}</p>
    </Link>
  );
}

function KpiCard({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <section className="animate-rise rounded-[18px] bg-surface p-6">
      <p className="text-[16px] text-text-secondary">{label}</p>
      {children}
    </section>
  );
}

function BigValue({ children }: { children: React.ReactNode }) {
  return <p className="mt-2 text-[38px] font-extrabold leading-[44px] tracking-[-0.02em]">{children}</p>;
}

function Goal({ note, label, ok }: { note: string; label: string; ok: boolean }) {
  return (
    <div className="mt-3 flex items-center justify-between gap-2">
      <span className="text-[14px] leading-[18px] text-text-muted">{note}</span>
      <span
        className={cx(
          "whitespace-nowrap rounded-full px-3 py-1 text-[14px] font-bold",
          ok ? "bg-secondary-soft text-secondary" : "bg-primary-soft text-primary-strong",
        )}
      >
        {label}
      </span>
    </div>
  );
}

function pct(v: number, digits: number) {
  return `${v.toLocaleString("fr-FR", { minimumFractionDigits: digits, maximumFractionDigits: digits })} %`;
}

/** « 2 j », « 5 h », « 12 min » depuis une date. */
function ago(iso: string, now: Date) {
  const min = Math.max(0, Math.round((now.getTime() - new Date(iso).getTime()) / 60000));
  if (min < 60) return `${min} min`;
  if (min < 48 * 60) return `${Math.round(min / 60)} h`;
  return `${Math.round(min / 1440)} j`;
}
