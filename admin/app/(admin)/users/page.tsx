import { Search } from "lucide-react";

import { ActionForm } from "@/components/action-form";
import {
  Avatar,
  buttonClass,
  EmptyState,
  ErrorState,
  fieldClass,
  FilterTabs,
  PageHeader,
  Pagination,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime, formatPhone, ROLE_LABEL } from "@/lib/format";
import { resetMfa, setAdmin } from "./actions";

export const metadata = { title: "Comptes" };

const LIMIT = 25;
const TABS = [
  { value: "", label: "Tous" },
  { value: "buyer", label: "Acheteurs" },
  { value: "seller", label: "Marchands" },
  { value: "driver", label: "Livreurs" },
  { value: "admin", label: "Admins" },
];

type Props = { searchParams: Promise<{ q?: string; role?: string; offset?: string }> };

export default async function UsersPage({ searchParams }: Props) {
  const sp = await searchParams;
  const q = (sp.q ?? "").trim().slice(0, 100);
  const role = sp.role ?? "";
  const offset = Number(sp.offset ?? 0) || 0;

  let page: { items: Schemas["User"][]; next_offset: number | null };
  let me: Schemas["User"];
  try {
    [page, me] = await Promise.all([
      api<{ items: Schemas["User"][]; next_offset: number | null }>("/v1/admin/users", {
        query: { q, role, limit: LIMIT, offset },
      }),
      api<Schemas["User"]>("/v1/me"),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const href = (r: string) => {
    const p = new URLSearchParams();
    if (q) p.set("q", q);
    if (r) p.set("role", r);
    const s = p.toString();
    return s ? `/users?${s}` : "/users";
  };

  return (
    <>
      <PageHeader
        overline="Plateforme"
        title="Comptes et droits d'accès"
        highlight="droits d'accès"
        description="Un même compte peut être acheteur, marchand et livreur. Les droits admin ouvrent le back-office : à donner avec parcimonie."
        actions={
          <form action="/users" role="search" className="flex gap-2">
            {role && <input type="hidden" name="role" value={role} />}
            <label className="sr-only" htmlFor="q">
              Rechercher un compte
            </label>
            <input
              id="q"
              name="q"
              defaultValue={q}
              placeholder="E-mail, téléphone ou prénom"
              className={fieldClass + " w-72"}
            />
            <button className={buttonClass("primary")}>
              <Search size={17} aria-hidden="true" /> Rechercher
            </button>
          </form>
        }
      />
      <FilterTabs current={role} tabs={TABS.map((t) => ({ ...t, href: href(t.value) }))} />
      {page.items.length === 0 ? (
        <EmptyState title="Aucun compte" message="Aucun compte ne correspond à cette recherche." />
      ) : (
        <Table head={["Compte", "Téléphone", "Rôles", "Créé le", "Droits admin"]}>
          {page.items.map((u) => {
            const isAdmin = u.roles.includes("admin");
            const name = [u.first_name, u.last_name].filter(Boolean).join(" ") || "Sans nom";
            return (
              <tr key={u.id}>
                <Td>
                  <div className="flex items-center gap-3">
                    <Avatar name={u.first_name || u.email || "?"} tone={isAdmin ? "imperial" : "berkeley"} />
                    <div className="min-w-0">
                      <p className="font-semibold">{name}</p>
                      <p className="text-[13px] text-text-muted">{u.email ?? "—"}</p>
                    </div>
                  </div>
                </Td>
                <Td>{formatPhone(u.phone)}</Td>
                <Td>
                  <div className="flex flex-wrap gap-1">
                    {u.roles.map((r) => (
                      <span
                        key={r}
                        className={
                          "rounded-full px-2.5 py-0.5 text-[12px] font-semibold " +
                          (r === "admin"
                            ? "bg-primary-soft text-primary-strong"
                            : "bg-secondary-soft text-tertiary")
                        }
                      >
                        {ROLE_LABEL[r] ?? r}
                      </span>
                    ))}
                  </div>
                </Td>
                <Td>{formatDateTime(u.created_at)}</Td>
                <Td>
                  {u.id === me.id ? (
                    <span className="text-[13px] text-text-muted">Votre compte</span>
                  ) : isAdmin ? (
                    <div className="flex flex-wrap gap-2">
                      <ActionForm
                        action={resetMfa}
                        label="Réinitialiser la 2FA"
                        variant="ghost"
                        hidden={{ id: u.id }}
                        confirm={{
                          title: `Réinitialiser la double vérification de ${name} ?`,
                          body: "Son application d'authentification est désactivée et toutes ses sessions sont coupées. À faire seulement après avoir vérifié son identité (téléphone perdu).",
                        }}
                        reason={{ label: "Motif", required: true }}
                      />
                      <ActionForm
                        action={setAdmin}
                        label="Retirer"
                        variant="outline"
                        hidden={{ id: u.id, grant: "false" }}
                        confirm={{
                          title: `Retirer les droits admin de ${name} ?`,
                          body: "L'accès au back-office est coupé dès sa prochaine page.",
                        }}
                        reason={{ label: "Motif", required: true }}
                      />
                    </div>
                  ) : (
                    <ActionForm
                      action={setAdmin}
                      label="Rendre admin"
                      variant="outline"
                      hidden={{ id: u.id, grant: "true" }}
                      confirm={{
                        title: `Donner les droits admin à ${name} ?`,
                        body: "Ce compte pourra valider les boutiques et les livreurs, annuler des commandes et rembourser.",
                      }}
                      reason={{ label: "Motif", required: true }}
                    />
                  )}
                </Td>
              </tr>
            );
          })}
        </Table>
      )}
      <Pagination
        basePath="/users"
        params={{ q, role }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
