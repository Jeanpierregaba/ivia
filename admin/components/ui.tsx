import Link from "next/link";

import type { Tone } from "@/lib/format";

// Composants de base (esprit shadcn/ui : le code vit dans le projet, thémé par les tokens de
// DESIGN.md). Serveur par défaut : aucun JavaScript envoyé au navigateur.

export function cx(...classes: (string | false | null | undefined)[]): string {
  return classes.filter(Boolean).join(" ");
}

const buttonVariants = {
  primary: "bg-tertiary text-white hover:bg-tertiary/90",
  danger: "bg-primary-strong text-white hover:bg-primary-strong/90",
  outline: "border border-border-input bg-surface text-text hover:bg-background-alt",
  ghost: "text-secondary hover:bg-secondary-soft",
} as const;

export type ButtonVariant = keyof typeof buttonVariants;

export function buttonClass(variant: ButtonVariant = "primary", extra?: string): string {
  return cx(
    "inline-flex h-10 items-center justify-center gap-2 rounded-full px-5 text-sm font-bold transition-colors",
    "disabled:cursor-not-allowed disabled:bg-border disabled:text-text-muted",
    buttonVariants[variant],
    extra,
  );
}

export function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return <section className={cx("rounded-card bg-surface p-6", className)}>{children}</section>;
}

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: React.ReactNode;
}) {
  return (
    <header className="mb-6 flex items-end justify-between gap-4">
      <div>
        <h1 className="text-[28px] font-bold leading-8 tracking-[-0.02em]">{title}</h1>
        {description && <p className="mt-1 text-text-secondary">{description}</p>}
      </div>
      {actions}
    </header>
  );
}

const toneClass: Record<Tone, string> = {
  success: "bg-success/10 text-success",
  warning: "bg-warning/10 text-warning",
  info: "bg-secondary-soft text-info",
  error: "bg-primary-soft text-error",
  muted: "bg-background-alt text-text-muted",
};

const toneIcon: Record<Tone, string> = { success: "✓", warning: "◷", info: "●", error: "✕", muted: "○" };

/** Statut avec icône et libellé : jamais porté par la couleur seule (DESIGN.md). */
export function StatusBadge({ label, tone }: { label: string; tone: Tone }) {
  return (
    <span
      className={cx(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[13px] font-semibold",
        toneClass[tone],
      )}
    >
      <span aria-hidden="true">{toneIcon[tone]}</span>
      {label}
    </span>
  );
}

export function Table({ head, children }: { head: string[]; children: React.ReactNode }) {
  return (
    <div className="overflow-x-auto rounded-card bg-surface">
      <table className="w-full text-left text-sm">
        <thead className="border-b border-border text-[12px] font-semibold uppercase tracking-[0.08em] text-text-muted">
          <tr>
            {head.map((h) => (
              <th key={h} scope="col" className="px-4 py-3">
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
  return <td className={cx("px-4 py-3 align-middle", className)}>{children}</td>;
}

export function EmptyState({ message }: { message: string }) {
  return <p className="rounded-card bg-surface px-6 py-10 text-center text-text-secondary">{message}</p>;
}

export function ErrorState({ message }: { message: string }) {
  return (
    <div role="alert" className="rounded-card bg-primary-soft px-6 py-4 text-error">
      <span aria-hidden="true">✕ </span>
      {message}
    </div>
  );
}

/** Onglets de filtre sous forme de liens (état dans l'URL : partageable, navigable au clavier). */
export function FilterTabs({
  tabs,
  current,
}: {
  tabs: { href: string; label: string; value: string }[];
  current: string;
}) {
  return (
    <nav aria-label="Filtres" className="mb-4 flex flex-wrap gap-2">
      {tabs.map((t) => (
        <Link
          key={t.value}
          href={t.href}
          aria-current={t.value === current ? "page" : undefined}
          className={cx(
            "rounded-full px-4 py-1.5 text-[13px] font-semibold",
            t.value === current
              ? "bg-secondary-soft text-tertiary"
              : "bg-surface text-text-secondary hover:bg-background-alt",
          )}
        >
          {t.label}
        </Link>
      ))}
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
    <nav aria-label="Pagination" className="mt-4 flex justify-end gap-2">
      {offset > 0 && (
        <Link className={buttonClass("outline")} href={href(Math.max(0, offset - limit))}>
          Précédent
        </Link>
      )}
      {nextOffset !== null && nextOffset !== undefined && (
        <Link className={buttonClass("outline")} href={href(nextOffset)}>
          Suivant
        </Link>
      )}
    </nav>
  );
}

export function DefinitionList({ items }: { items: [string, React.ReactNode][] }) {
  return (
    <dl className="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2">
      {items.map(([k, v]) => (
        <div key={k} className="contents">
          <dt className="text-text-muted">{k}</dt>
          <dd>{v}</dd>
        </div>
      ))}
    </dl>
  );
}
