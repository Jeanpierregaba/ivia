"use client";

import {
  Banknote,
  ChartLine,
  Hexagon,
  MapPin,
  BellRing,
  BookOpen,
  Briefcase,
  Building2,
  Cross,
  HandCoins,
  Pill,
  SlidersHorizontal,
  TriangleAlert,
  ClipboardList,
  CreditCard,
  Download,
  LayoutGrid,
  LogOut,
  Megaphone,
  TicketPercent,
  Package,
  ReceiptText,
  ScrollText,
  Settings2,
  ShieldCheck,
  Store,
  Truck,
  Users,
  X,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { LogoTile } from "./brand";
import { cx } from "./ui";

export type SidebarCounts = { orders: number; refunds: number; shops: number; drivers: number };

type Item = {
  href: string;
  label: string;
  icon: typeof LayoutGrid;
  count?: keyof SidebarCounts;
  urgent?: boolean;
};

// Sections de la maquette B03 ; Comptes et Référentiels complètent « Système ».
const sections: { title: string; items: Item[] }[] = [
  {
    title: "Opérations",
    items: [
      { href: "/orders", label: "Commandes", icon: ClipboardList, count: "orders" },
      { href: "/payments", label: "Paiements", icon: CreditCard },
      { href: "/refunds", label: "Remboursements", icon: Banknote, count: "refunds", urgent: true },
    ],
  },
  {
    title: "Réseau",
    items: [
      { href: "/business", label: "Ivia Business", icon: Briefcase },
      { href: "/shops", label: "Boutiques", icon: Store, count: "shops" },
      { href: "/drivers", label: "Livreurs", icon: Truck, count: "drivers" },
      { href: "/driver-incidents", label: "Signalements livreurs", icon: TriangleAlert },
      { href: "/driver-settings", label: "Réglages partenaires", icon: SlidersHorizontal },
      { href: "/properties", label: "Immobilier", icon: Building2 },
    ],
  },
  {
    title: "Santé",
    items: [
      { href: "/pharmacies", label: "Pharmacies", icon: Cross },
      { href: "/medicine-alerts", label: "Alertes médicament", icon: BellRing },
      { href: "/medicine-payments", label: "Paiements santé", icon: HandCoins },
      { href: "/medicines", label: "Médicaments", icon: Pill },
      { href: "/pharmacy-settings", label: "Réglages santé", icon: SlidersHorizontal },
    ],
  },
  {
    title: "Carte",
    items: [
      { href: "/places", label: "Lieux", icon: MapPin },
      { href: "/zones", label: "Zones et tarifs", icon: Hexagon },
      { href: "/geo-metrics", label: "Coûts de la carte", icon: ChartLine },
    ],
  },
  {
    title: "Marketing",
    items: [
      { href: "/promo", label: "Publicité", icon: Megaphone },
      { href: "/coupons", label: "Codes promo", icon: TicketPercent },
      { href: "/products", label: "Produits IVI", icon: Package },
    ],
  },
  {
    title: "Finances",
    items: [
      { href: "/settlements", label: "Relevés marchands", icon: ReceiptText },
      { href: "/deliveries", label: "Export livraisons", icon: Download },
    ],
  },
  {
    title: "Système",
    items: [
      { href: "/audit", label: "Journal des actions", icon: ScrollText },
      { href: "/settings", label: "Paramètres", icon: Settings2 },
      { href: "/users", label: "Comptes", icon: Users },
      { href: "/security", label: "Sécurité", icon: ShieldCheck },
      { href: "/referentials", label: "Référentiels", icon: BookOpen },
    ],
  },
];

function initialsOf(first: string, last: string, email: string) {
  const v = ((first[0] ?? "") + (last[0] ?? "")).toUpperCase();
  return v || (email[0] ?? "A").toUpperCase();
}

/** Texte qui s'efface en douceur quand la barre est repliée. */
function Label({
  hidden,
  children,
  className,
}: {
  hidden: boolean;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <span
      className={cx(
        "overflow-hidden whitespace-nowrap transition-[opacity,max-width,transform] duration-500 ease-[cubic-bezier(0.16,1,0.3,1)]",
        hidden ? "max-w-0 -translate-x-2 opacity-0" : "max-w-[220px] opacity-100",
        className,
      )}
    >
      {children}
    </span>
  );
}

/**
 * Barre latérale Berkeley Blue de la maquette B03, avec les pastilles des choses à traiter.
 * Repliée : pictogrammes seuls (libellé en info-bulle), pastilles réduites à un point.
 */
export function Sidebar({
  firstName,
  lastName,
  email,
  counts,
  collapsed = false,
  toggle,
  onClose,
}: {
  firstName: string;
  lastName: string;
  email: string;
  counts: SidebarCounts;
  collapsed?: boolean;
  toggle?: React.ReactNode;
  onClose?: () => void;
}) {
  const path = usePathname();
  const on = (href: string) => (href === "/" ? path === "/" : path.startsWith(href));
  const fullName = [firstName, lastName].filter(Boolean).join(" ") || email;
  // Le tiroir (petit écran) est toujours déplié.
  const mini = collapsed && !onClose;

  return (
    <aside className="flex h-full flex-col overflow-hidden bg-tertiary text-white lg:h-screen">
      <div
        className={cx(
          "flex items-center gap-3 pb-5 pt-6 transition-[padding] duration-500",
          mini ? "flex-col px-3" : "px-5",
        )}
      >
        <Link href="/" className="group/logo flex min-w-0 flex-1 items-center gap-3" title="Tableau de bord">
          <span className="shrink-0 transition-transform duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)] group-hover/logo:-rotate-6 group-hover/logo:scale-110">
            <LogoTile size={mini ? 44 : 48} />
          </span>
          <Label hidden={mini} className="leading-tight">
            <span className="block text-[17px] font-extrabold">ivia</span>
            <span className="block text-[14px] text-white/65">Back-office</span>
          </Label>
        </Link>
        {toggle}
        {onClose && (
          <button
            type="button"
            onClick={onClose}
            aria-label="Fermer le menu"
            className="grid size-10 shrink-0 place-items-center rounded-[12px] text-white/75 transition-colors hover:bg-white/10 hover:text-white lg:hidden"
          >
            <X size={20} aria-hidden="true" />
          </button>
        )}
      </div>

      <nav
        aria-label="Navigation principale"
        className="sidebar-scroll flex-1 overflow-y-auto overflow-x-hidden px-3 pb-4"
      >
        <Link
          href="/"
          title={mini ? "Tableau de bord" : undefined}
          aria-current={on("/") ? "page" : undefined}
          className={cx(
            "nav-item mb-5 flex h-[52px] items-center gap-3 rounded-[14px] text-[14px] font-bold",
            mini ? "justify-center px-0" : "px-4",
            on("/")
              ? "bg-white text-tertiary shadow-[0_10px_24px_-14px_rgba(0,0,0,0.6)]"
              : "text-white/85 hover:bg-white/10",
          )}
        >
          <LayoutGrid
            size={19}
            aria-hidden="true"
            strokeWidth={on("/") ? 2.4 : 1.9}
            className="nav-icon shrink-0"
          />
          <Label hidden={mini}>Tableau de bord</Label>
        </Link>

        {sections.map((s) => (
          <div key={s.title} className="mb-4">
            <div className="relative mb-1.5 h-5">
              <p
                className={cx(
                  "absolute inset-x-4 whitespace-nowrap text-[12px] font-bold uppercase tracking-[0.12em] text-white/45 transition-opacity duration-300",
                  mini && "opacity-0",
                )}
              >
                {s.title}
              </p>
              <span
                aria-hidden="true"
                className={cx(
                  "absolute left-1/2 top-1/2 h-px w-8 -translate-x-1/2 bg-white/15 transition-opacity duration-300",
                  mini ? "opacity-100" : "opacity-0",
                )}
              />
            </div>
            {s.items.map((item) => {
              const Icon = item.icon;
              const active = on(item.href);
              const n = item.count ? counts[item.count] : 0;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  title={mini ? item.label + (n > 0 ? ` (${n})` : "") : undefined}
                  aria-current={active ? "page" : undefined}
                  className={cx(
                    "nav-item group relative flex h-[44px] items-center gap-3 rounded-[12px] text-[14px]",
                    mini ? "justify-center px-0" : "px-4",
                    active
                      ? "bg-white font-bold text-tertiary shadow-[0_10px_24px_-14px_rgba(0,0,0,0.6)]"
                      : "text-white/85 hover:bg-white/10 hover:text-white",
                  )}
                >
                  <Icon
                    size={19}
                    aria-hidden="true"
                    strokeWidth={active ? 2.4 : 1.9}
                    className="nav-icon shrink-0"
                  />
                  <Label hidden={mini} className="flex-1">
                    {item.label}
                  </Label>
                  {n > 0 &&
                    (mini ? (
                      <span
                        aria-label={`${n} à traiter`}
                        className={cx(
                          "absolute right-2 top-2 size-2.5 rounded-full ring-2 ring-tertiary",
                          item.urgent ? "bg-primary" : "bg-secondary",
                        )}
                      />
                    ) : (
                      <span
                        className={cx(
                          "min-w-7 rounded-full px-2 py-0.5 text-center text-[13px] font-bold tabular-nums",
                          item.urgent
                            ? "bg-primary text-white"
                            : active
                              ? "bg-tertiary text-white"
                              : "bg-white/15 text-white",
                        )}
                        aria-label={`${n} à traiter`}
                      >
                        {n}
                      </span>
                    ))}
                </Link>
              );
            })}
          </div>
        ))}
      </nav>

      <div
        className={cx(
          "flex items-center gap-3 border-t border-white/10 py-4 transition-[padding] duration-500",
          mini ? "flex-col px-2" : "px-5",
        )}
      >
        <span
          title={mini ? fullName : undefined}
          className="grid size-11 shrink-0 place-items-center rounded-full bg-secondary text-[14px] font-bold"
        >
          {initialsOf(firstName, lastName, email)}
        </span>
        <Label hidden={mini} className="min-w-0 flex-1">
          <span className="block truncate text-[14px] font-bold">{fullName}</span>
          <span className="block text-[13px] text-white/60">Administrateur</span>
        </Label>
        <a
          href="/logout"
          title="Se déconnecter"
          className="grid size-9 shrink-0 place-items-center rounded-full text-white/70 transition-[background-color,color,transform] duration-300 hover:bg-white/10 hover:text-white active:scale-90"
        >
          <LogOut size={18} aria-label="Se déconnecter" />
        </a>
      </div>
    </aside>
  );
}
