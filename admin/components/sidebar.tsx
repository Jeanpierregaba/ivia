"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cx } from "./ui";

const sections = [
  { href: "/", label: "Tableau de bord" },
  { href: "/shops", label: "Boutiques" },
  { href: "/drivers", label: "Livreurs" },
  { href: "/orders", label: "Commandes" },
  { href: "/refunds", label: "Remboursements" },
  { href: "/settings", label: "Paramètres" },
  { href: "/audit", label: "Journal des actions" },
];

export function Sidebar({ name }: { name: string }) {
  const path = usePathname();
  const active = (href: string) => (href === "/" ? path === "/" : path.startsWith(href));

  return (
    <aside className="sticky top-0 flex h-screen flex-col bg-tertiary px-4 py-6 text-white">
      <p className="px-3 text-[28px] font-bold leading-8 tracking-[-0.02em]">ivia</p>
      <p className="mb-8 px-3 text-[13px] text-white/70">Back-office</p>
      <nav aria-label="Navigation principale" className="flex flex-1 flex-col gap-1">
        {sections.map((s) => (
          <Link
            key={s.href}
            href={s.href}
            aria-current={active(s.href) ? "page" : undefined}
            className={cx(
              "rounded-full px-3 py-2 text-sm font-semibold",
              active(s.href) ? "bg-white text-tertiary" : "text-white/85 hover:bg-white/10",
            )}
          >
            {s.label}
          </Link>
        ))}
      </nav>
      <div className="border-t border-white/15 px-3 pt-4 text-sm">
        <p className="truncate text-white/85">{name}</p>
        <a
          href="/logout"
          className="mt-1 inline-block font-semibold text-white underline-offset-4 hover:underline"
        >
          Se déconnecter
        </a>
      </div>
    </aside>
  );
}
