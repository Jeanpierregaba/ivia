"use client";

import {
  Banknote,
  BellRing,
  BookOpen,
  Building2,
  Cross,
  HandCoins,
  Pill,
  SlidersHorizontal,
  ClipboardList,
  CreditCard,
  Download,
  LayoutGrid,
  LogOut,
  Megaphone,
  Package,
  ReceiptText,
  ScrollText,
  Settings2,
  ShieldCheck,
  Store,
  Truck,
  Users,
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
      { href: "/shops", label: "Boutiques", icon: Store, count: "shops" },
      { href: "/drivers", label: "Livreurs", icon: Truck, count: "drivers" },
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
    title: "Marketing",
    items: [
      { href: "/promo", label: "Publicité", icon: Megaphone },
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

/** Barre latérale Berkeley Blue de la maquette B03, avec les pastilles des choses à traiter. */
export function Sidebar({
  firstName,
  lastName,
  email,
  counts,
}: {
  firstName: string;
  lastName: string;
  email: string;
  counts: SidebarCounts;
}) {
  const path = usePathname();
  const on = (href: string) => (href === "/" ? path === "/" : path.startsWith(href));
  const fullName = [firstName, lastName].filter(Boolean).join(" ") || email;

  return (
    <aside className="sticky top-0 flex h-screen flex-col bg-tertiary text-white">
      <div className="flex items-center gap-3 px-5 pb-6 pt-6">
        <LogoTile size={50} />
        <div className="leading-tight">
          <p className="text-[20px] font-extrabold">ivia</p>
          <p className="text-[14px] text-white/65">Back-office</p>
        </div>
      </div>

      <nav aria-label="Navigation principale" className="flex-1 overflow-y-auto px-3 pb-4">
        <Link
          href="/"
          aria-current={on("/") ? "page" : undefined}
          className={cx(
            "mb-5 flex h-[54px] items-center gap-3 rounded-[14px] px-4 text-[17px] font-bold transition-colors",
            on("/") ? "bg-white text-tertiary" : "text-white/85 hover:bg-white/10",
          )}
        >
          <span
            aria-hidden="true"
            className={cx("size-[18px] rounded-[5px]", on("/") ? "bg-primary" : "border-2 border-white/60")}
          />
          Tableau de bord
        </Link>

        {sections.map((s) => (
          <div key={s.title} className="mb-5">
            <p className="mb-1.5 px-4 text-[12px] font-bold uppercase tracking-[0.12em] text-white/45">
              {s.title}
            </p>
            {s.items.map((item) => {
              const Icon = item.icon;
              const active = on(item.href);
              const n = item.count ? counts[item.count] : 0;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  aria-current={active ? "page" : undefined}
                  className={cx(
                    "group flex h-[46px] items-center gap-3 rounded-[12px] px-4 text-[16px] transition-colors",
                    active
                      ? "bg-white font-bold text-tertiary"
                      : "text-white/85 hover:bg-white/10 hover:text-white",
                  )}
                >
                  <Icon size={19} aria-hidden="true" strokeWidth={active ? 2.4 : 1.9} className="shrink-0" />
                  <span className="flex-1 truncate">{item.label}</span>
                  {n > 0 && (
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
                  )}
                </Link>
              );
            })}
          </div>
        ))}
      </nav>

      <div className="flex items-center gap-3 border-t border-white/10 px-5 py-4">
        <span className="grid size-11 shrink-0 place-items-center rounded-full bg-secondary text-[15px] font-bold">
          {initialsOf(firstName, lastName, email)}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[16px] font-bold">{fullName}</p>
          <p className="text-[13px] text-white/60">Administrateur</p>
        </div>
        <a
          href="/logout"
          title="Se déconnecter"
          className="grid size-9 place-items-center rounded-full text-white/70 hover:bg-white/10 hover:text-white"
        >
          <LogOut size={18} aria-label="Se déconnecter" />
        </a>
      </div>
    </aside>
  );
}
