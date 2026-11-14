import {
  AlertTriangle,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Circle,
  Clock3,
  Info,
  Inbox,
  XCircle,
} from "lucide-react";
import Link from "next/link";

import type { Tone } from "@/lib/format";

// Composants de base, dans le langage visuel des apps (mobile/packages/ui) : cartes blanches sans
// ombre sur fond #F3F4F6, rayons 14/18, boutons pilules, surtitres en capitales, partie colorée
// des titres. Serveur par défaut : aucun JavaScript envoyé au navigateur.

export function cx(...classes: (string | false | null | undefined)[]): string {
  return classes.filter(Boolean).join(" ");
}

const buttonVariants = {
  primary: "bg-tertiary text-white hover:bg-[#163c6b]",
  imperial: "bg-primary text-white hover:bg-primary-strong",
  danger: "bg-primary-strong text-white hover:bg-[#8f0b17]",
  outline: "border border-border-input bg-surface text-text hover:bg-background-alt",
  ghost: "text-secondary hover:bg-secondary-soft",
} as const;

export type ButtonVariant = keyof typeof buttonVariants;

export function buttonClass(variant: ButtonVariant = "primary", extra?: string): string {
  return cx(
    "inline-flex h-11 items-center justify-center gap-2 rounded-full px-6 text-[14px] font-bold transition-[background-color,color,transform,box-shadow] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] hover:-translate-y-px active:translate-y-0 active:scale-[0.97]",
    "disabled:cursor-not-allowed disabled:bg-border disabled:text-text-muted",
    buttonVariants[variant],
    extra,
  );
}

export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <section className={cx("card-soft rounded-field bg-surface p-5 sm:p-6", className)}>{children}</section>
  );
}

/** Titre de section de carte, avec pictogramme sur pastille pâle (comme les apps). */
export function CardTitle({
  icon,
  children,
  aside,
}: {
  icon?: React.ReactNode;
  children: React.ReactNode;
  aside?: React.ReactNode;
}) {
  return (
    <div className="mb-5 flex items-center justify-between gap-3">
      <h2 className="flex items-center gap-3 text-[15px] font-bold leading-[20px]">
        {icon && (
          <span className="grid size-9 place-items-center rounded-card bg-secondary-soft text-tertiary">
            {icon}
          </span>
        )}
        {children}
      </h2>
      {aside}
    </div>
  );
}

/**
 * En-tête de page : surtitre en capitales, titre dont une partie est colorée (règle « partie
 * colorée des titres » de DESIGN.md), description.
 */
export function PageHeader({
  overline,
  title,
  highlight,
  description,
  actions,
}: {
  overline?: string;
  title: string;
  highlight?: string;
  description?: string;
  actions?: React.ReactNode;
}) {
  const at = highlight ? title.indexOf(highlight) : -1;
  return (
    <header className="animate-rise mb-8 flex flex-wrap items-end justify-between gap-x-6 gap-y-4">
      <div className="max-w-[720px]">
        {overline && (
          <p className="mb-1.5 text-[12px] font-semibold uppercase leading-4 tracking-[0.08em] text-secondary">
            {overline}
          </p>
        )}
        <h1 className="text-[24px] font-bold leading-[32px] tracking-[-0.02em] sm:text-[28px] sm:leading-[32px]">
          {at >= 0 && highlight ? (
            <>
              {title.slice(0, at)}
              <span className="text-primary">{highlight}</span>
              {title.slice(at + highlight.length)}
            </>
          ) : (
            title
          )}
        </h1>
        {description && <p className="mt-2 text-text-secondary">{description}</p>}
      </div>
      {actions}
    </header>
  );
}

const toneClass: Record<Tone, string> = {
  success: "bg-[#E6F2EC] text-success",
  warning: "bg-[#FBEFE3] text-warning",
  info: "bg-secondary-soft text-info",
  error: "bg-primary-soft text-error",
  muted: "bg-background text-text-muted",
};

const toneIcon = {
  success: CheckCircle2,
  warning: Clock3,
  info: Circle,
  error: XCircle,
  muted: Circle,
} as const;

/** Statut avec icône et libellé : jamais porté par la couleur seule (DESIGN.md). */
export function StatusBadge({ label, tone }: { label: string; tone: Tone }) {
  const Icon = toneIcon[tone];
  return (
    <span
      className={cx(
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full py-1 pl-2 pr-3 text-[13px] font-semibold",
        toneClass[tone],
      )}
    >
      <Icon size={14} aria-hidden="true" />
      {label}
    </span>
  );
}

export function Table({ head, children }: { head: string[]; children: React.ReactNode }) {
  return (
    <div className="overflow-x-auto rounded-field bg-surface">
      <table className="w-full min-w-[640px] text-left text-[14px]">
        <thead>
          <tr className="border-b border-border">
            {head.map((h, i) => (
              <th
                key={`${h}-${i}`}
                scope="col"
                className="px-5 pb-3 pt-4 text-[12px] font-semibold uppercase tracking-[0.08em] text-text-muted"
              >
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-border">{children}</tbody>
      </table>
    </div>
  );
}

export function Td({ children, className }: { children: React.ReactNode; className?: string }) {
  return <td className={cx("px-5 py-4 align-middle", className)}>{children}</td>;
}

/** Vide : pictogramme et phrase qui explique (DESIGN.md « États à toujours prévoir »). */
export function EmptyState({ title, message }: { title?: string; message: string }) {
  return (
    <div className="flex flex-col items-center rounded-field bg-surface px-6 py-14 text-center">
      <span className="mb-4 grid size-14 place-items-center rounded-full bg-background text-text-muted">
        <Inbox size={26} aria-hidden="true" />
      </span>
      {title && <p className="text-[15px] font-bold">{title}</p>}
      <p className="mt-1 max-w-md text-text-secondary">{message}</p>
    </div>
  );
}

export function ErrorState({ message }: { message: string }) {
  return (
    <div role="alert" className="flex items-start gap-3 rounded-field bg-primary-soft px-6 py-5 text-error">
      <AlertTriangle size={20} aria-hidden="true" className="mt-0.5 shrink-0" />
      <div>
        <p className="font-bold">Impossible d&apos;afficher cette page</p>
        <p className="mt-0.5">{message}</p>
      </div>
    </div>
  );
}

/** Encart d'information : pictogramme et texte (comme IviaInfoCard des apps). */
export function InfoCard({
  children,
  tone = "info",
}: {
  children: React.ReactNode;
  tone?: "info" | "warning";
}) {
  return (
    <div className="flex items-start gap-3 rounded-field bg-surface px-5 py-4 text-text-secondary">
      {tone === "info" ? (
        <Info size={18} aria-hidden="true" className="mt-0.5 shrink-0 text-secondary" />
      ) : (
        <AlertTriangle size={18} aria-hidden="true" className="mt-0.5 shrink-0 text-warning" />
      )}
      <div>{children}</div>
    </div>
  );
}

/** Puces de filtre (état dans l'URL : partageable, navigable au clavier). */
export function FilterTabs({
  tabs,
  current,
}: {
  tabs: { href: string; label: string; value: string }[];
  current: string;
}) {
  return (
    <nav aria-label="Filtres" className="mb-5 flex flex-wrap gap-2">
      {tabs.map((t) => {
        const active = t.value === current;
        return (
          <Link
            key={t.value}
            href={t.href}
            aria-current={active ? "page" : undefined}
            className={cx(
              "inline-flex h-10 items-center rounded-full px-4 text-[13px] font-semibold transition-[background-color,color,transform] duration-300 active:scale-95",
              active
                ? "bg-tertiary text-white"
                : "bg-surface text-text-secondary hover:bg-secondary-soft hover:text-tertiary",
            )}
          >
            {t.label}
          </Link>
        );
      })}
    </nav>
  );
}

export function Pagination({
  basePath,
  params,
  offset,
  nextOffset,
  limit,
}: {
  basePath: string;
  params: Record<string, string | undefined>;
  offset: number;
  nextOffset: number | null | undefined;
  limit: number;
}) {
  const href = (o: number) => {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) if (v) q.set(k, v);
    if (o > 0) q.set("offset", String(o));
    const s = q.toString();
    return s ? `${basePath}?${s}` : basePath;
  };
  if (offset === 0 && (nextOffset === null || nextOffset === undefined)) return null;
  return (
    <nav aria-label="Pagination" className="mt-5 flex justify-end gap-2">
      {offset > 0 && (
        <Link className={buttonClass("outline")} href={href(Math.max(0, offset - limit))}>
          <ChevronLeft size={18} aria-hidden="true" /> Précédent
        </Link>
      )}
      {nextOffset !== null && nextOffset !== undefined && (
        <Link className={buttonClass("outline")} href={href(nextOffset)}>
          Suivant <ChevronRight size={18} aria-hidden="true" />
        </Link>
      )}
    </nav>
  );
}

export function DefinitionList({ items }: { items: [string, React.ReactNode][] }) {
  return (
    <dl className="divide-y divide-border">
      {items.map(([k, v]) => (
        <div key={k} className="flex flex-wrap justify-between gap-x-6 gap-y-1 py-3 first:pt-0 last:pb-0">
          <dt className="text-text-muted">{k}</dt>
          <dd className="text-right font-semibold">{v}</dd>
        </div>
      ))}
    </dl>
  );
}

/** Initiale dans un cercle de couleur (boutique, livreur, admin). */
export function Avatar({
  name,
  tone = "berkeley",
  size = 40,
}: {
  name: string;
  tone?: "berkeley" | "cobalt" | "imperial";
  size?: number;
}) {
  const bg = { berkeley: "bg-tertiary", cobalt: "bg-secondary", imperial: "bg-primary" }[tone];
  return (
    <span
      aria-hidden="true"
      className={cx("inline-grid shrink-0 place-items-center rounded-full font-bold text-white", bg)}
      style={{ width: size, height: size, fontSize: size * 0.42 }}
    >
      {(name.trim()[0] ?? "?").toUpperCase()}
    </span>
  );
}

/** Champ de saisie (DESIGN.md) : contour 3:1 au repos, Imperial 2 px quand il est actif. */
export const fieldClass =
  "h-11 w-full rounded-field border border-border-input bg-surface px-4 text-[14px] outline-none focus:border-2 focus:border-primary focus:px-[15px]";

/** Libellé au-dessus du champ, précision facultative en dessous. */
export function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-[13px] font-semibold text-text-secondary">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-[12px] text-text-muted">{hint}</span>}
    </label>
  );
}
