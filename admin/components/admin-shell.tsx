"use client";

import { Menu, PanelLeftClose, PanelLeftOpen } from "lucide-react";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

import { LogoTile } from "./brand";
import { Sidebar, type SidebarCounts } from "./sidebar";
import { cx } from "./ui";

const KEY = "ivia-admin-sidebar";

/**
 * Cadre de l'espace admin, sur toute la largeur de l'écran : barre latérale repliable (réglage
 * gardé dans le navigateur), tiroir avec voile sur petit écran, contenu qui s'adapte en douceur.
 */
export function AdminShell({
  firstName,
  lastName,
  email,
  counts,
  children,
}: {
  firstName: string;
  lastName: string;
  email: string;
  counts: SidebarCounts;
  children: React.ReactNode;
}) {
  const [collapsed, setCollapsed] = useState(false);
  const [drawer, setDrawer] = useState(false);
  const path = usePathname();

  // Réglage relu après le premier affichage (le serveur ne connaît pas le navigateur).
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCollapsed(window.localStorage.getItem(KEY) === "1");
  }, []);

  // Changement de page : le tiroir se referme.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setDrawer(false);
  }, [path]);

  // Échap ferme le tiroir.
  useEffect(() => {
    if (!drawer) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setDrawer(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [drawer]);

  const toggle = () => {
    setCollapsed((c) => {
      window.localStorage.setItem(KEY, c ? "0" : "1");
      return !c;
    });
  };

  return (
    <div
      className="admin-shell min-h-screen w-full lg:grid lg:grid-cols-[var(--side)_minmax(0,1fr)] lg:transition-[grid-template-columns] lg:duration-500 lg:ease-[cubic-bezier(0.16,1,0.3,1)]"
      style={{ ["--side" as string]: collapsed ? "88px" : "288px" }}
      data-collapsed={collapsed ? "" : undefined}
    >
      {/* Barre du haut, petit écran */}
      <header className="sticky top-0 z-30 flex h-16 items-center gap-3 bg-tertiary px-4 text-white shadow-[0_8px_24px_-12px_rgba(14,46,84,0.6)] lg:hidden">
        <button
          type="button"
          onClick={() => setDrawer(true)}
          aria-label="Ouvrir le menu"
          aria-expanded={drawer}
          className="grid size-11 place-items-center rounded-[12px] transition-[background-color,transform] duration-300 hover:bg-white/10 active:scale-90"
        >
          <Menu size={22} aria-hidden="true" />
        </button>
        <LogoTile size={36} />
        <span className="text-[15px] font-extrabold">Back-office</span>
      </header>

      {/* Voile du tiroir */}
      <div
        aria-hidden="true"
        onClick={() => setDrawer(false)}
        className={cx(
          "fixed inset-0 z-40 bg-tertiary/45 backdrop-blur-[3px] transition-opacity duration-500 lg:hidden",
          drawer ? "opacity-100" : "pointer-events-none opacity-0",
        )}
      />

      <div
        className={cx(
          "fixed inset-y-0 left-0 z-50 w-[288px] max-w-[86vw] transition-transform duration-500 ease-[cubic-bezier(0.16,1,0.3,1)]",
          "lg:sticky lg:top-0 lg:z-auto lg:h-screen lg:w-auto lg:max-w-none lg:translate-x-0",
          drawer ? "translate-x-0 shadow-[24px_0_60px_-20px_rgba(10,26,48,0.5)]" : "-translate-x-full",
        )}
      >
        <Sidebar
          firstName={firstName}
          lastName={lastName}
          email={email}
          counts={counts}
          collapsed={collapsed}
          onClose={drawer ? () => setDrawer(false) : undefined}
          toggle={
            <button
              type="button"
              onClick={toggle}
              aria-label={collapsed ? "Déplier le menu" : "Replier le menu"}
              title={collapsed ? "Déplier le menu" : "Replier le menu"}
              className="group/toggle hidden size-10 shrink-0 place-items-center rounded-[12px] text-white/75 transition-[background-color,color,transform] duration-300 hover:bg-white/12 hover:text-white active:scale-90 lg:grid"
            >
              <span className="grid transition-transform duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)] group-hover/toggle:scale-110">
                {collapsed ? (
                  <PanelLeftOpen size={20} aria-hidden="true" />
                ) : (
                  <PanelLeftClose size={20} aria-hidden="true" />
                )}
              </span>
            </button>
          }
        />
      </div>

      <main className="min-w-0 px-4 pb-16 pt-6 sm:px-6 lg:px-10 lg:pt-9 2xl:px-12">{children}</main>
    </div>
  );
}
