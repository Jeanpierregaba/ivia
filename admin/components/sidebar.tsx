"use client";

import {
  Banknote,
  ClipboardList,
  LayoutGrid,
  LogOut,
  ScrollText,
  Settings2,
  Store,
  Truck,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { Logo } from "./brand";
import { cx } from "./ui";

const operations = [
  { href: "/", label: "Tableau de bord", icon: LayoutGrid },
  { href: "/shops", label: "Boutiques", icon: Store },
  { href: "/drivers", label: "Livreurs", icon: Truck },
  { href: "/orders", label: "Commandes", icon: ClipboardList },
  { href: "/refunds", label: "Remboursements", icon: Banknote },
];

const platform = [
  { href: "/settings", label: "Paramètres", icon: Settings2 },
  { href: "/audit", label: "Journal des actions", icon: ScrollText },
];

/** Barre latérale Berkeley Blue (DESIGN.md « Back-office »), logotype blanc de la charte. */
export function Sidebar({ name, email }: { name: string; email: string }) {
  const path = usePathname();
  const active = (href: string) => (href === "/" ? path === "/" : path.startsWith(href));

  const item = (s: (typeof operations)[number]) => {
    const Icon = s.icon;
    const on = active(s.href);
    return (
      <Link
        key={s.href}
        href={s.href}
        aria-current={on ? "page" : undefined}
        className={cx(
          "flex h-11 items-center gap-3 rounded-full px-4 text-[15px] font-semibold transition-colors",
          on ? "bg-white text-tertiary" : "text-white/80 hover:bg-white/10 hover:text-white",
        )}
      >
        <Icon size={19} aria-hidden="true" strokeWidth={on ? 2.4 : 2} />
        {s.label}
      </Link>
    );
  };

  return (
    <aside className="sticky top-0 flex h-screen flex-col bg-tertiary px-4 pb-5 pt-7 text-white">
      <div className="mb-9 flex items-center gap-3 px-3">
        <Logo color="white" height={30} />
        <span className="rounded-full bg-white/15 px-2.5 py-1 text-[12px] font-semibold uppercase tracking-[0.08em] text-white/85">
          Admin
        </span>
      </div>

      <nav aria-label="Navigation principale" className="flex flex-1 flex-col gap-1">
        <p className="mb-1 px-4 text-[12px] font-semibold uppercase tracking-[0.08em] text-white/50">
          Opérations
        </p>
        {operations.map(item)}
        <p className="mb-1 mt-6 px-4 text-[12px] font-semibold uppercase tracking-[0.08em] text-white/50">
          Plateforme
        </p>
        {platform.map(item)}
      </nav>

      <div className="flex items-center gap-3 rounded-field bg-white/10 p-3">
        <span className="grid size-10 shrink-0 place-items-center rounded-full bg-primary text-[17px] font-bold">
          {(name.trim()[0] ?? "A").toUpperCase()}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[15px] font-semibold">{name}</p>
          <p className="truncate text-[13px] text-white/60">{email}</p>
        </div>
        <a
          href="/logout"
          title="Se déconnecter"
          className="grid size-9 place-items-center rounded-full text-white/80 hover:bg-white/10 hover:text-white"
        >
          <LogOut size={18} aria-label="Se déconnecter" />
        </a>
      </div>
    </aside>
  );
}
