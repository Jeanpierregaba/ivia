import { redirect } from "next/navigation";

import { Sidebar, type SidebarCounts } from "@/components/sidebar";
import { api, ApiError, type Schemas } from "@/lib/api";

// Toutes les pages de l'espace admin : la session est vérifiée auprès de l'API à chaque
// affichage (rôle admin et double vérification par code, ADR 0011 ; un rôle retiré coupe
// l'accès immédiatement).
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const [me, session] = await Promise.all([
    api<Schemas["User"]>("/v1/me"),
    api<Schemas["SessionInfo"]>("/v1/auth/session"),
  ]);
  if (!me.roles.includes("admin")) redirect("/logout");
  if (!session.mfa_verified) redirect("/login/code");

  // Pastilles : la vue d'ensemble les fournit ; en cas d'erreur, la navigation reste utilisable.
  let counts: SidebarCounts = { orders: 0, refunds: 0, shops: 0, drivers: 0 };
  try {
    counts = (await api<Schemas["AdminOverview"]>("/v1/admin/overview")).sidebar;
  } catch (err) {
    if (!(err instanceof ApiError)) throw err;
  }

  return (
    <div className="grid min-h-screen grid-cols-[300px_minmax(0,1fr)]">
      <Sidebar firstName={me.first_name} lastName={me.last_name} email={me.email ?? ""} counts={counts} />
      <main className="min-w-0 px-11 pb-16 pt-9">
        <div className="mx-auto max-w-[1440px]">{children}</div>
      </main>
    </div>
  );
}
