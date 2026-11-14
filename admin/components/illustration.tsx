import { Check } from "lucide-react";
import Link from "next/link";

import { cx } from "./ui";

// Briques des illustrations, reprises des apps (mobile/packages/ui/lib/src/illustration.dart) :
// grandes cartes de couleur, fiches inclinées, tuiles de mosaïque, pastilles cochées.
// Seul endroit où les cartes ont une ombre (DESIGN.md).

export const illustrationShadow = "shadow-[0_10px_24px_rgba(14,46,84,0.16)]";

export function Tilted({
  deg,
  children,
  className,
}: {
  deg: number;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={className} style={{ transform: `rotate(${deg}deg)` }}>
      {children}
    </div>
  );
}

/** Pastille blanche avec une coche (« Livreur activé », « Paiement reçu »). */
export function CheckPill({ label, color = "bg-tertiary" }: { label: string; color?: string }) {
  return (
    <span
      className={cx(
        "inline-flex h-[50px] items-center gap-2.5 rounded-full bg-surface pl-2.5 pr-[18px]",
        illustrationShadow,
      )}
    >
      <span className={cx("grid size-[26px] place-items-center rounded-full text-white", color)}>
        <Check size={16} strokeWidth={3} aria-hidden="true" />
      </span>
      <span className="text-[14px] font-semibold text-text">{label}</span>
    </span>
  );
}

export type MosaicCorner = "tl" | "tr" | "bl" | "br" | "none";

const corner: Record<MosaicCorner, string> = {
  tl: "rounded-tile rounded-tl-[18px]",
  tr: "rounded-tile rounded-tr-[18px]",
  bl: "rounded-tile rounded-bl-[18px]",
  br: "rounded-tile rounded-br-[18px]",
  none: "rounded-tile",
};

/**
 * Tuile de mosaïque : légende en haut, valeur en bas. Les tuiles sont séparées de 8 px, rayon 6 px
 * sauf le coin tourné vers l'extérieur de la grille (18 px), comme dans les apps.
 */
export function MosaicTile({
  caption,
  value,
  detail,
  href,
  tone,
  cornerAt = "none",
  icon,
}: {
  caption: string;
  value: string;
  detail?: string;
  href?: string;
  tone: "imperial" | "berkeley" | "cobalt" | "cornell" | "soft";
  cornerAt?: MosaicCorner;
  icon?: React.ReactNode;
}) {
  const colors = {
    imperial: "bg-primary text-white",
    berkeley: "bg-tertiary text-white",
    cobalt: "bg-secondary text-white",
    cornell: "bg-primary-strong text-white",
    soft: "bg-surface text-text",
  }[tone];
  const body = (
    <>
      <span className="flex items-start justify-between gap-3">
        <span className="text-[13px] leading-[18px] opacity-85">{caption}</span>
        {icon && <span className="opacity-85">{icon}</span>}
      </span>
      <span className="mt-auto">
        <span className="block text-[40px] font-bold leading-[34px] tracking-[-0.02em]">{value}</span>
        {detail && <span className="mt-1 block text-[13px] leading-[18px] opacity-85">{detail}</span>}
      </span>
    </>
  );
  const cls = cx("flex min-h-[148px] flex-col p-5 transition-transform", colors, corner[cornerAt]);
  return href ? (
    <Link href={href} className={cx(cls, "hover:-translate-y-0.5")}>
      {body}
    </Link>
  ) : (
    <div className={cls}>{body}</div>
  );
}

/** Emplacement hachuré d'une image absente (logo, photo), comme IviaImagePlaceholder. */
export function Hatch({ className }: { className?: string }) {
  return (
    <span
      aria-hidden="true"
      className={cx("block", className)}
      style={{
        backgroundColor: "var(--color-border)",
        backgroundImage:
          "repeating-linear-gradient(45deg, var(--color-background-alt) 0 3px, transparent 3px 12px)",
      }}
    />
  );
}
