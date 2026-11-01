import type { Metadata } from "next";

import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Connexion" };

export default function LoginPage() {
  return (
    <main className="grid min-h-screen place-items-center bg-tertiary px-4">
      <div className="w-full max-w-sm rounded-card bg-surface p-8">
        <p className="text-[34px] font-bold leading-[38px] tracking-[-0.02em] text-primary">ivia</p>
        <h1 className="mt-1 text-[22px] font-bold leading-7">Back-office</h1>
        <p className="mb-6 mt-1 text-text-secondary">Réservé à l&apos;équipe ivia.</p>
        <LoginForm />
      </div>
    </main>
  );
}
