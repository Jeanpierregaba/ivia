import { redirect } from "next/navigation";

import { Sidebar } from "@/components/sidebar";
import { api, type Schemas } from "@/lib/api";

// Toutes les pages de l'espace admin : la session est vérifiée auprès de l'API à chaque
// affichage (un rôle admin retiré coupe l'accès immédiatement, ADR 0006).
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const me = await api<Schemas["User"]>("/v1/me");
  if (!me.roles.includes("admin")) redirect("/logout");

  return (
    <div className="grid min-h-screen grid-cols-[248px_1fr]">
      <Sidebar name={me.first_name || me.email || "Admin"} />
      <main className="min-w-0 px-10 py-8">{children}</main>
    </div>
  );
}
