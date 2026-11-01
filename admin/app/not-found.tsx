import { ArrowLeft } from "lucide-react";
import Link from "next/link";

import { Logo } from "@/components/brand";
import { buttonClass } from "@/components/ui";

export default function NotFound() {
  return (
    <main className="grid min-h-screen place-items-center bg-background px-4">
      <div className="flex flex-col items-center text-center">
        <Logo color="berkeley" height={36} />
        <p className="mt-10 text-[12px] font-semibold uppercase tracking-[0.08em] text-secondary">
          Erreur 404
        </p>
        <h1 className="mt-1.5 text-[34px] font-bold leading-[38px] tracking-[-0.02em]">
          Page <span className="text-primary">introuvable</span>
        </h1>
        <p className="mt-2 text-text-secondary">Cette ressource n&apos;existe pas ou plus.</p>
        <Link href="/" className={buttonClass("primary", "mt-6")}>
          <ArrowLeft size={16} aria-hidden="true" /> Retour au tableau de bord
        </Link>
      </div>
    </main>
  );
}
