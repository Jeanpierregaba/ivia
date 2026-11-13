import Link from "next/link";

import { cx } from "@/components/ui";
import type { Schemas } from "@/lib/api";
import { ORDER_STATUS } from "@/lib/format";

// Blocs du tableau de bord (maquette B03), rendus côté serveur ; l'interaction passe par les liens
// (puces dans l'URL) et le survol en CSS. Données : GET /v1/admin/overview.

const LETTERS = ["D", "L", "M", "M", "J", "V", "S"]; // getUTCDay() : 0 = dimanche
const dayTitle = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "UTC",
  weekday: "short",
  day: "numeric",
  month: "short",
});
const group = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
const F = (n: number) => `${group.format(n)} F`;

function Card({
  title,
  aside,
  children,
  className,
}: {
  title: string;
  aside?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={cx("dash-card animate-rise rounded-[22px] bg-surface p-6", className)}>
      <div className="mb-5 flex items-center justify-between gap-4">
        <h2 className="text-[17px] font-extrabold tracking-[-0.01em]">{title}</h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

function RedLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link href={href} className="text-[14px] font-bold text-primary hover:underline">
      {children}
    </Link>
  );
}

/** Commandes payées des 14 derniers jours : livraison (rouge) et retrait (bleu nuit) empilés. */
export function PaidChart({ days }: { days: Schemas["OverviewDay"][] }) {
  const max = Math.max(1, ...days.map((d) => d.delivery + d.pickup));
  return (
    <Card title="Commandes payées · 14 derniers jours">
      <div className="-mt-2 mb-6 flex gap-6 text-[14px] text-text-secondary">
        <span className="flex items-center gap-2">
          <span className="size-3 rounded-[3px] bg-primary" /> Livraison
        </span>
        <span className="flex items-center gap-2">
          <span className="size-3 rounded-[3px] bg-tertiary" /> Retrait
        </span>
      </div>
      <ol className="flex h-[260px] items-end gap-[14px]" aria-label="Commandes payées par jour">
        {days.map((d, i) => {
          const last = i === days.length - 1;
          const total = d.delivery + d.pickup;
          const date = new Date(`${d.day}T00:00:00Z`);
          return (
            <li key={d.day} className="group relative flex h-full flex-1 flex-col items-center justify-end">
              {last && <span className="mb-1.5 text-[14px] font-extrabold">{total}</span>}
              <span
                className="animate-grow flex w-full origin-bottom flex-col justify-end gap-[3px]"
                style={{
                  height: `${Math.max(total ? 6 : 0, (total / max) * 82)}%`,
                  animationDelay: `${i * 35}ms`,
                }}
              >
                {d.delivery > 0 && (
                  <span
                    className={cx("w-full rounded-t-[8px]", last ? "bg-primary" : "bg-[#EF4050]")}
                    style={{ flexGrow: d.delivery }}
                  />
                )}
                {d.pickup > 0 && (
                  <span
                    className={cx(
                      "w-full",
                      d.delivery ? "" : "rounded-t-[8px]",
                      last ? "bg-tertiary" : "bg-[#34506F]",
                    )}
                    style={{ flexGrow: d.pickup }}
                  />
                )}
              </span>
              <span className={cx("mt-3 text-[14px]", last ? "font-extrabold text-text" : "text-text-muted")}>
                {LETTERS[date.getUTCDay()]}
              </span>
              {/* Infobulle au survol */}
              <span className="pointer-events-none absolute bottom-[calc(100%-36px)] z-10 hidden whitespace-nowrap rounded-[10px] bg-tertiary px-3 py-2 text-[13px] text-white shadow-lg group-hover:block">
                <strong className="block">{dayTitle.format(date)}</strong>
                {d.delivery} livraison{d.delivery > 1 ? "s" : ""} · {d.pickup} retrait
                {d.pickup > 1 ? "s" : ""}
              </span>
            </li>
          );
        })}
      </ol>
    </Card>
  );
}

/** Livreurs maintenant et paiements de la période. */
export function DriversPanel({
  drivers,
  payments,
  periodLabel,
}: {
  drivers: Schemas["OverviewDrivers"];
  payments: Schemas["OverviewPayments"];
  periodLabel: string;
}) {
  const rows = [
    { label: "Disponibles", n: drivers.available, color: "bg-secondary" },
    { label: "En mission", n: drivers.busy, color: "bg-primary" },
    { label: "Hors ligne", n: drivers.offline, color: "bg-[#C9CFD8]" },
    { label: "Suspendus", n: drivers.suspended, color: "bg-tertiary" },
  ];
  const total = Math.max(
    1,
    rows.reduce((s, r) => s + r.n, 0),
  );
  return (
    <Card title="Livreurs maintenant" aside={<RedLink href="/drivers">Voir les livreurs</RedLink>}>
      <div className="mb-5 flex h-3 gap-[3px] overflow-hidden rounded-full bg-background" aria-hidden="true">
        {rows.map((r) =>
          r.n > 0 ? (
            <span
              key={r.label}
              className={cx("h-full transition-[flex-grow] duration-700", r.color)}
              style={{ flexGrow: r.n / total }}
            />
          ) : null,
        )}
      </div>
      <ul className="space-y-3.5">
        {rows.map((r) => (
          <li key={r.label} className="flex items-center justify-between text-[15px]">
            <span className="flex items-center gap-3">
              <span className={cx("size-2.5 rounded-full", r.color)} /> {r.label}
            </span>
            <strong className="tabular-nums">{r.n}</strong>
          </li>
        ))}
      </ul>
      <div className="mt-5 border-t border-border pt-4">
        <p className="mb-2 text-[14px] text-text-secondary">Paiements · {periodLabel.toLowerCase()}</p>
        <ul className="space-y-2 text-[15px]">
          <li className="flex items-center justify-between">
            <span className="flex items-center gap-3">
              <span className="size-2.5 rounded-full bg-secondary" /> Réussis
            </span>
            <strong className="tabular-nums">
              {payments.succeeded} · {F(payments.succeeded_xof)}
            </strong>
          </li>
          <li className="flex items-center justify-between">
            <Link href="/payments?status=pending" className="flex items-center gap-3 hover:underline">
              <span className="size-2.5 rounded-full bg-text-muted" /> En attente
            </Link>
            <strong className="tabular-nums">{payments.pending}</strong>
          </li>
          <li className="flex items-center justify-between">
            <Link href="/payments?status=failed" className="flex items-center gap-3 hover:underline">
              <span className="size-2.5 rounded-full bg-primary-strong" /> Échoués ou expirés
            </Link>
            <strong className="tabular-nums">{payments.failed}</strong>
          </li>
        </ul>
      </div>
    </Card>
  );
}

/** Statut affiché dans « Commandes en cours », avec sa couleur. */
function statusPill(o: Schemas["OverviewActiveOrder"]): [string, string] {
  if (o.handover_locked) return ["Code bloqué", "bg-primary-soft text-primary-strong"];
  switch (o.status) {
    case "awaiting_seller":
      return ["Payée · à accepter", "bg-primary-soft text-primary"];
    case "awaiting_driver":
      return ["Prête · sans livreur", "bg-[#FBEFD5] text-[#8A5A00]"];
    case "accepted":
      return ["Acceptée", "bg-secondary-soft text-secondary"];
    case "preparing":
      return ["En préparation", "bg-secondary-soft text-secondary"];
    case "ready_for_pickup":
      return ["Prête · retrait", "bg-secondary-soft text-secondary"];
    case "driver_assigned":
      return ["Livreur assigné", "bg-secondary-soft text-secondary"];
    case "picked_up":
      return ["En route", "bg-secondary-soft text-secondary"];
    default:
      return [ORDER_STATUS[o.status]?.label ?? o.status, "bg-background text-text-secondary"];
  }
}

function minutesSince(iso: string, now: string) {
  return Math.max(0, Math.round((new Date(now).getTime() - new Date(iso).getTime()) / 60000));
}

function duration(min: number) {
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  return h < 48 ? `${h} h ${String(min % 60).padStart(2, "0")}` : `${Math.floor(h / 24)} j`;
}

/** Commandes en cours, filtrées par puce (groupe dans l'URL). */
export function ActiveOrders({
  active,
  now,
  chipHref,
}: {
  active: Schemas["OverviewActive"];
  now: string;
  chipHref: (group: string) => string;
}) {
  const chips = [
    { value: "", label: "Toutes", n: active.all },
    { value: "to_accept", label: "À accepter", n: active.to_accept },
    { value: "without_driver", label: "Sans livreur", n: active.without_driver },
    { value: "locked", label: "Bloquées", n: active.locked },
  ];
  return (
    <Card title="Commandes en cours" aside={<RedLink href="/orders">Toutes les commandes</RedLink>}>
      <nav aria-label="Filtrer les commandes en cours" className="mb-5 flex flex-wrap gap-2.5">
        {chips.map((c) => (
          <Link
            key={c.value}
            href={chipHref(c.value)}
            scroll={false}
            aria-current={active.group === c.value ? "true" : undefined}
            className={cx(
              "rounded-full px-5 py-2.5 text-[14px] font-bold transition-colors",
              active.group === c.value
                ? "bg-tertiary text-white"
                : "bg-background text-text hover:bg-secondary-soft",
            )}
          >
            {c.label} · {c.n}
          </Link>
        ))}
      </nav>
      {active.items.length === 0 ? (
        <p className="rounded-[14px] bg-background px-5 py-8 text-center text-text-secondary">
          Aucune commande dans ce groupe pour le moment.
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left text-[14px]">
            <thead>
              <tr className="border-b border-border text-[14px] text-text-secondary">
                {["N°", "Boutique", "Acheteur", "Mode", "Montant", "Statut", "Depuis"].map((h) => (
                  <th key={h} scope="col" className="px-2 pb-3 font-bold first:pl-1">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {active.items.map((o) => {
                const [label, color] = statusPill(o);
                const min = minutesSince(o.since, now);
                const late = (o.status === "awaiting_seller" || o.status === "awaiting_driver") && min >= 10;
                return (
                  <tr key={o.id} className="transition-colors hover:bg-background/70">
                    <td className="py-4 pl-1 pr-2">
                      <Link href={`/orders/${o.id}`} className="font-extrabold hover:text-primary">
                        #{o.number}
                      </Link>
                    </td>
                    <td className="max-w-[180px] truncate px-2 font-bold">
                      <Link href={`/orders/${o.id}`} className="hover:underline">
                        {o.shop_name || "—"}
                      </Link>
                    </td>
                    <td className="px-2 text-text-secondary">{o.buyer_name}</td>
                    <td className="px-2 text-text-secondary">
                      {o.fulfillment === "delivery" ? "Livraison" : "Retrait"}
                    </td>
                    <td className="whitespace-nowrap px-2 font-extrabold">{F(o.total_xof)}</td>
                    <td className="px-2">
                      <span
                        className={cx(
                          "whitespace-nowrap rounded-full px-3 py-1 text-[14px] font-bold",
                          color,
                        )}
                      >
                        {label}
                      </span>
                    </td>
                    <td
                      className={cx(
                        "whitespace-nowrap px-2",
                        late ? "font-extrabold text-[#8A5A00]" : "text-text-secondary",
                      )}
                    >
                      {duration(min)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}

// Verbe de chaque action du journal ; la cible lisible (target_label) suit.
const VERBS: Record<string, string> = {
  "shop.approve": "a validé la boutique",
  "shop.reject": "a refusé la boutique",
  "shop.suspend": "a suspendu la boutique",
  "shop.reinstate": "a rétabli la boutique",
  "driver.approve": "a validé le livreur",
  "driver.reject": "a refusé le livreur",
  "driver.suspend": "a suspendu le livreur",
  "driver.reinstate": "a rétabli le livreur",
  "order.cancel": "a annulé la commande",
  "order.confirm_return": "a confirmé le retour de la commande",
  "order.unassign_driver": "a retiré le livreur de la commande",
  "order.unlock_handover": "a débloqué le code de la commande",
  "payment.refund_requested": "a lancé un remboursement",
  "settings.update": "a modifié les paramètres",
  "settlement.create": "a créé un relevé",
  "settlement.mark_settled": "a marqué réglé un relevé",
  "settlement.delete": "a supprimé un relevé",
  "category.create": "a ajouté la catégorie",
  "category.update": "a modifié la catégorie",
  "shop_category.create": "a ajouté la catégorie de boutique",
  "shop_category.update": "a modifié la catégorie de boutique",
  "neighborhood.create": "a ajouté le quartier",
  "neighborhood.update": "a modifié le quartier",
  "user.grant_admin": "a donné les droits admin à",
  "user.revoke_admin": "a retiré les droits admin à",
};

const hm = new Intl.DateTimeFormat("fr-FR", { timeZone: "Africa/Lome", hour: "2-digit", minute: "2-digit" });
const dayKey = new Intl.DateTimeFormat("fr-CA", { timeZone: "Africa/Lome" });
const shortDay = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Africa/Lome",
  day: "numeric",
  month: "short",
});

function when(iso: string, now: string) {
  const d = new Date(iso);
  const n = new Date(now);
  if (dayKey.format(d) === dayKey.format(n)) return hm.format(d);
  if (dayKey.format(d) === dayKey.format(new Date(n.getTime() - 86400_000))) return `Hier, ${hm.format(d)}`;
  return `${shortDay.format(d)}, ${hm.format(d)}`;
}

/** Dernières actions des admins. */
export function AuditFeed({ lines, now }: { lines: Schemas["OverviewAuditLine"][]; now: string }) {
  return (
    <Card title="Journal des actions" aside={<RedLink href="/audit">Tout voir</RedLink>}>
      {lines.length === 0 ? (
        <p className="text-text-secondary">Aucune action pour l&apos;instant.</p>
      ) : (
        <ol className="space-y-5">
          {lines.map((l) => (
            <li key={l.id} className="flex gap-3.5">
              <span className="grid size-10 shrink-0 place-items-center rounded-full bg-background text-[13px] font-extrabold text-tertiary">
                {l.admin_initials}
              </span>
              <div className="min-w-0 text-[14px] leading-[20px]">
                <p>
                  <strong>{l.admin_name}</strong> {VERBS[l.action] ?? l.action}
                  {l.target_label && (
                    <>
                      {" "}
                      <strong>{l.target_label}</strong>
                    </>
                  )}
                </p>
                <p className="mt-0.5 text-[14px] text-text-muted">{when(l.created_at, now)}</p>
              </div>
            </li>
          ))}
        </ol>
      )}
    </Card>
  );
}
