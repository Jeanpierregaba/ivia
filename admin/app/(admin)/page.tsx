import {
  ArrowUpRight,
  Banknote,
  Bell,
  CheckCircle2,
  LockKeyhole,
  PackageSearch,
  RotateCcw,
  Route,
  Search,
  ShoppingBag,
  Store,
  Timer,
  Truck,
  Wallet,
} from "lucide-react";
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
      <h2 className="dash-section mb-3">À traiter</h2>
      <div className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
        <TodoCard
          tone="#ED1C2F"
          icon={<Banknote size={20} aria-hidden="true" />}
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
          icon={<Store size={20} aria-hidden="true" />}
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
          icon={<Truck size={20} aria-hidden="true" />}
          value={o.todo.drivers}
          action="Examiner"
          title="Livreurs à valider"
          detail={o.todo.drivers ? "Documents reçus, à vérifier" : "Aucun dossier en attente"}
          href="/drivers?review_status=pending_review"
          delay={120}
        />
        <TodoCard
          tone="#AA0E1B"
          icon={<LockKeyhole size={20} aria-hidden="true" />}
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
          icon={<PackageSearch size={20} aria-hidden="true" />}
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
      <h2 className="dash-section mb-3 mt-8">Indicateurs</h2>
      <div className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
        <KpiCard label="Commandes payées" icon={<ShoppingBag size={17} aria-hidden="true" />}>
          <BigValue>
            <AnimatedNumber value={k.paid_orders} />
          </BigValue>
          <p className="mt-3 text-[14px] text-text-muted">
            {delta === null ? "Pas de comparaison" : `${delta >= 0 ? "+" : ""}${delta} % ${versus}`}
          </p>
        </KpiCard>
        <KpiCard label="Volume des ventes" icon={<Wallet size={17} aria-hidden="true" />}>
          <BigValue>
            <AnimatedNumber value={k.gmv_xof} kind="xof" />
          </BigValue>
          <p className="mt-3 text-[14px] text-text-muted">Commission : {F(k.commission_xof)}</p>
        </KpiCard>
        <KpiCard label="Annulées ou remboursées" icon={<RotateCcw size={17} aria-hidden="true" />}>
          <BigValue>{pct(k.cancellation_rate_pct, 1)}</BigValue>
          <Goal note="Sur 30 jours" label="Objectif < 5 %" ok={k.cancellation_rate_pct < 5} />
        </KpiCard>
        <KpiCard label="Livreur assigné < 10 min" icon={<Timer size={17} aria-hidden="true" />}>
          <BigValue>{pct(k.assigned_within_10_min_pct, 0)}</BigValue>
          <Goal note="Commandes prêtes" label="Objectif 80 %" ok={k.assigned_within_10_min_pct >= 80} />
        </KpiCard>
        <KpiCard label="Prête → livrée" icon={<Route size={17} aria-hidden="true" />}>
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

      <h2 className="dash-section mb-3 mt-8">Activité</h2>
      <div className="mb-4 grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1.75fr)_minmax(0,1fr)]">
        <PaidChart days={o.paid_per_day} />
        <DriversPanel
          drivers={o.drivers}
          payments={o.payments}
          periodLabel={PERIODS.find((p) => p.value === period)!.label}
        />
      </div>

      <div className="grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1.75fr)_minmax(0,1fr)]">
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
    <header className="dash-hero animate-rise relative z-30 mb-8 overflow-visible rounded-[28px] px-6 py-7 text-white sm:px-8 sm:py-8">
      <span aria-hidden="true" className="dash-hero-glow dash-hero-glow-a" />
      <span aria-hidden="true" className="dash-hero-glow dash-hero-glow-b" />
      <div className="relative flex flex-wrap items-end justify-between gap-6">
        <div>
          <p className="text-[13px] font-semibold uppercase tracking-[0.14em] text-white/60">
            Tableau de bord
          </p>
          <h1 className="mt-1 text-[28px] font-extrabold leading-[34px] tracking-[-0.03em] sm:text-[34px] sm:leading-[40px]">
            Bonjour {props.firstName}
          </h1>
          <p className="mt-2 text-[14px] text-white/75">
            {props.date} · Lomé · <LiveRefresh generatedAt={props.generatedAt} />
          </p>
        </div>
        <div className="flex w-full flex-wrap items-center gap-2.5 sm:w-auto">
          <form action="/search" role="search" className="relative min-w-0 flex-1 sm:flex-none">
            <Search
              size={18}
              aria-hidden="true"
              className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-white/70"
            />
            <label htmlFor="global-search" className="sr-only">
              Rechercher une commande, une boutique, un livreur, un téléphone
            </label>
            <input
              id="global-search"
              name="q"
              placeholder="Commande, boutique, livreur, téléphone…"
              className="h-12 w-full rounded-[14px] bg-white/12 pl-11 pr-4 text-[14px] text-white outline-none ring-1 ring-white/20 backdrop-blur transition-[background-color,box-shadow] duration-300 placeholder:text-white/60 focus:bg-white/20 focus:ring-2 focus:ring-white/60 sm:w-[260px] 2xl:w-[340px]"
            />
          </form>
          <PeriodMenu current={props.period} options={props.periodOptions} />
          <Link
            href="/notifications"
            aria-label={props.unread ? `${props.unread} notification(s) non lue(s)` : "Notifications"}
            className="relative grid size-12 place-items-center rounded-[14px] bg-white/12 ring-1 ring-white/20 backdrop-blur transition-colors hover:bg-white/20"
          >
            <Bell size={20} aria-hidden="true" />
            {props.unread > 0 && (
              <span className="animate-live absolute right-2.5 top-2.5 size-2.5 rounded-full bg-primary ring-2 ring-tertiary" />
            )}
          </Link>
        </div>
      </div>
    </header>
  );
}

function TodoCard(props: {
  tone: string;
  icon: React.ReactNode;
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
      style={{ animationDelay: `${props.delay}ms`, ["--tone" as string]: props.tone }}
      className={cx(
        "dash-card animate-rise group relative flex min-w-0 flex-col overflow-hidden rounded-[22px] bg-surface p-5",
        !idle && "dash-card-hot",
      )}
    >
      <div className="flex items-center justify-between gap-3">
        <span className="dash-chip grid size-11 place-items-center rounded-[14px]">{props.icon}</span>
        {idle ? (
          <span className="inline-flex items-center gap-1 rounded-full bg-[#E6F2EC] px-2.5 py-1 text-[12px] font-bold text-success">
            <CheckCircle2 size={13} aria-hidden="true" /> À jour
          </span>
        ) : (
          <span className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[12px] font-bold text-text-secondary transition-colors group-hover:bg-tertiary group-hover:text-white">
            {props.action}
            <ArrowUpRight
              size={13}
              aria-hidden="true"
              className="transition-transform duration-300 group-hover:translate-x-0.5 group-hover:-translate-y-0.5"
            />
          </span>
        )}
      </div>
      <span
        className="mt-4 text-[32px] font-extrabold leading-none tracking-[-0.02em] tabular-nums"
        style={{ color: idle ? "#A3ADBB" : props.tone }}
      >
        <AnimatedNumber value={props.value} />
      </span>
      <p className="mt-2 text-[15px] font-bold leading-[20px]">{props.title}</p>
      <p className="mt-1 text-[13px] leading-[18px] text-text-muted">{props.detail}</p>
    </Link>
  );
}

function KpiCard({
  label,
  icon,
  children,
}: {
  label: string;
  icon: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="dash-card animate-rise min-w-0 rounded-[22px] bg-surface p-5">
      <div className="flex items-center gap-2.5">
        <span className="grid size-9 place-items-center rounded-[12px] bg-secondary-soft text-secondary">
          {icon}
        </span>
        <p className="text-[13px] font-semibold text-text-secondary">{label}</p>
      </div>
      {children}
    </section>
  );
}

function BigValue({ children }: { children: React.ReactNode }) {
  return (
    <p className="mt-3 text-[26px] font-extrabold leading-[32px] tracking-[-0.02em] tabular-nums">
      {children}
    </p>
  );
}

function Goal({ note, label, ok }: { note: string; label: string; ok: boolean }) {
  return (
    <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
      <span className="text-[13px] leading-[18px] text-text-muted">{note}</span>
      <span
        className={cx(
          "whitespace-nowrap rounded-full px-2.5 py-0.5 text-[12px] font-bold",
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
