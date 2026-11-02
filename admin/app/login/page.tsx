import { Store, Truck } from "lucide-react";
import type { Metadata } from "next";

import { Logo } from "@/components/brand";
import { CheckPill, Hatch, illustrationShadow, Tilted } from "@/components/illustration";
import { cx } from "@/components/ui";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Connexion" };

export default function LoginPage() {
  return (
    <main className="grid min-h-screen grid-cols-[minmax(0,1fr)_minmax(420px,520px)] bg-background max-[1023px]:grid-cols-1">
      {/* Illustration (mêmes briques que la présentation des apps) */}
      <section aria-hidden="true" className="relative overflow-hidden bg-tertiary max-[1023px]:hidden">
        <div className="absolute left-14 top-12">
          <Logo color="white" height={40} />
        </div>
        <div className="absolute inset-x-14 bottom-16">
          <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-white/60">Back-office</p>
          <p className="mt-2 max-w-[460px] text-[34px] font-bold leading-[38px] tracking-[-0.02em] text-white">
            Gardez la main sur <span className="text-primary">toute la plateforme</span>.
          </p>
          <p className="mt-3 max-w-[460px] text-white/75">
            Boutiques et livreurs à valider, commandes, remboursements : tout se décide ici.
          </p>
        </div>

        <Tilted deg={-3} className="absolute left-[14%] top-[22%] w-[340px]">
          <div className={cx("rounded-field bg-surface p-4", illustrationShadow)}>
            <div className="flex items-center gap-3">
              <span className="grid size-11 place-items-center rounded-card bg-secondary-soft text-tertiary">
                <Store size={22} />
              </span>
              <div className="flex-1">
                <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-secondary">
                  Boutique à valider
                </p>
                <p className="text-[17px] font-bold text-text">Chez Afi · Tokoin</p>
              </div>
            </div>
            <div className="mt-4 grid grid-cols-3 gap-2">
              <Hatch className="h-16 rounded-tile rounded-bl-[18px]" />
              <Hatch className="h-16 rounded-tile" />
              <Hatch className="h-16 rounded-tile rounded-br-[18px]" />
            </div>
            <div className="mt-4 flex gap-2">
              <span className="flex-1 rounded-full bg-tertiary py-2.5 text-center text-[13px] font-bold text-white">
                Publier
              </span>
              <span className="flex-1 rounded-full border border-border-input py-2.5 text-center text-[13px] font-bold text-text">
                Refuser
              </span>
            </div>
          </div>
        </Tilted>

        <Tilted deg={4} className="absolute left-[44%] top-[50%] w-[280px]">
          <div className={cx("rounded-field bg-surface p-4", illustrationShadow)}>
            <div className="flex items-center gap-3">
              <span className="grid size-11 place-items-center rounded-full bg-secondary text-white">
                <Truck size={20} />
              </span>
              <div>
                <p className="text-[15px] font-bold text-text">Yao · Moto</p>
                <p className="text-[13px] text-text-muted">Pièce d&apos;identité · Permis</p>
              </div>
            </div>
          </div>
        </Tilted>

        <Tilted deg={-2} className="absolute left-[30%] top-[66%]">
          <CheckPill label="Livreur activé" color="bg-secondary" />
        </Tilted>
      </section>

      {/* Formulaire */}
      <section className="flex flex-col justify-center px-10 py-12 max-[1023px]:px-6">
        <div className="mx-auto w-full max-w-[400px]">
          <div className="mb-10 hidden max-[1023px]:block">
            <Logo color="berkeley" height={36} />
          </div>
          <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-secondary">Équipe ivia</p>
          <h1 className="mt-1.5 text-[34px] font-bold leading-[38px] tracking-[-0.02em]">
            Connexion au <span className="text-primary">back-office</span>
          </h1>
          <p className="mb-8 mt-2 text-text-secondary">
            Saisissez votre adresse : nous vous envoyons un code à 6 chiffres. Accès réservé aux comptes
            admin.
          </p>
          <LoginForm />
        </div>
      </section>
    </main>
  );
}
