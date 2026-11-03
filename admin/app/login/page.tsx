import type { Metadata } from "next";
import Link from "next/link";

import { AuthNote, AuthShell } from "./auth-shell";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Connexion" };

// Maquette B01 : e-mail et mot de passe, puis code de vérification (B02).
export default function LoginPage() {
  return (
    <AuthShell>
      <div className="animate-rise">
        <p className="text-[13px] font-bold uppercase tracking-[0.12em] text-primary">
          Espace administrateur
        </p>
        <h1 className="mt-3 text-[44px] font-extrabold leading-[48px] tracking-[-0.03em]">Connexion</h1>
        <p className="mb-9 mt-3 text-[17px] leading-[25px] text-text-secondary">
          Saisissez votre e-mail professionnel et votre mot de passe. Nous vous envoyons ensuite un code à
          usage unique.
        </p>
        <LoginForm />
        <AuthNote>
          Accès réservé aux comptes ayant le rôle administrateur. Chaque action est enregistrée dans le
          journal.
        </AuthNote>
        <p className="mt-6 flex flex-wrap justify-between gap-2 text-[14px] text-text-muted">
          <Link href="/login/forgot" className="font-semibold text-secondary hover:underline">
            Mot de passe oublié ?
          </Link>
          <span>Problème d&apos;accès ? Contactez le responsable technique.</span>
        </p>
      </div>
    </AuthShell>
  );
}
