import { LogoTile } from "@/components/brand";

/**
 * Habillage des écrans de connexion (maquettes B01, B02) : panneau Berkeley avec la tuile ivia, la
 * mosaïque de la charte et le slogan, formulaire à droite.
 */
export function AuthShell({ children }: { children: React.ReactNode }) {
  return (
    <main className="grid min-h-screen grid-cols-[minmax(0,7fr)_minmax(420px,5fr)] bg-surface max-[1023px]:grid-cols-1">
      <section
        aria-hidden="true"
        className="relative flex min-h-[640px] flex-col justify-between overflow-hidden bg-tertiary px-[54px] pb-16 pt-[54px] max-[1023px]:hidden"
      >
        <div className="flex items-center gap-4">
          <LogoTile size={46} />
          <span className="text-[16px] font-bold text-white">Back-office</span>
        </div>

        {/* Mosaïque de la charte, coupée par le bord droit du panneau */}
        <div className="pointer-events-none absolute right-[-60px] top-1/2 grid -translate-y-[62%] grid-cols-[148px_148px] gap-3">
          <span className="animate-tile-in h-[148px] rounded-[18px] rounded-tl-[44px] bg-primary [animation-delay:60ms]" />
          <span className="animate-tile-in h-[148px] rounded-[18px] bg-secondary [animation-delay:140ms]" />
          <span className="animate-tile-in h-[148px] rounded-[18px] rounded-bl-[44px] bg-[#16365f] [animation-delay:220ms]" />
          <span className="animate-tile-in h-[148px] rounded-[18px] bg-primary-strong [animation-delay:300ms]" />
        </div>

        <div className="relative max-w-[420px]">
          <p className="text-[36px] font-extrabold leading-[38px] tracking-[-0.03em] text-white">
            Toute la plateforme, au même endroit.
          </p>
          <p className="mt-5 text-[15px] leading-[22px] text-white/70">
            Boutiques, livreurs, commandes, paiements et remboursements de Lomé.
          </p>
        </div>
      </section>

      <section className="flex flex-col justify-center px-[78px] py-12 max-[1279px]:px-12 max-[1023px]:px-6">
        <div className="mx-auto w-full max-w-[430px]">
          <div className="mb-10 hidden items-center gap-3 max-[1023px]:flex">
            <LogoTile size={40} />
            <span className="text-[15px] font-bold">Back-office</span>
          </div>
          {children}
        </div>
      </section>
    </main>
  );
}

/** Encart d'information (point Cobalt), comme sous le bouton de B01. */
export function AuthNote({ children }: { children: React.ReactNode }) {
  return (
    <div className="mt-7 flex items-start gap-3 rounded-[14px] bg-background px-5 py-4 text-[13px] leading-[19px] text-text-secondary">
      <span aria-hidden="true" className="mt-1.5 size-2 shrink-0 rounded-full bg-secondary" />
      <p>{children}</p>
    </div>
  );
}

export const authFieldClass =
  "h-[52px] w-full rounded-[14px] border border-border-input bg-surface px-4 text-[14px] outline-none focus-visible:outline-none transition-colors placeholder:text-text-muted focus:border-2 focus:border-primary focus:px-[15px]";
