import { ClipboardList, Store, Users } from "lucide-react";
import Link from "next/link";

import { Avatar, Card, CardTitle, EmptyState, ErrorState, PageHeader, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatPhone, formatXOF, ORDER_STATUS, ROLE_LABEL, SHOP_STATUS, statusOf } from "@/lib/format";

export const metadata = { title: "Recherche" };

type Props = { searchParams: Promise<{ q?: string }> };

/**
 * Recherche globale de l'en-tête : commande par numéro (« 1052 », « #1052 », « IV-001052 »),
 * boutique par nom, compte par e-mail, téléphone ou prénom (acheteurs, marchands, livreurs).
 */
export default async function SearchPage({ searchParams }: Props) {
  const q = ((await searchParams).q ?? "").trim().slice(0, 100);
  const digits = q.replace(/\D/g, "");
  const isNumber = /^[#\s]*(iv-?)?\d+$/i.test(q);

  let orders: Schemas["AdminOrder"][] = [];
  let shops: Schemas["Shop"][] = [];
  let users: Schemas["User"][] = [];
  if (q) {
    try {
      [orders, shops, users] = await Promise.all([
        isNumber && digits
          ? api<{ items: Schemas["AdminOrder"][] }>("/v1/admin/orders", {
              query: { number: Number(digits), limit: 5 },
            }).then((r) => r.items)
          : Promise.resolve([]),
        api<{ items: Schemas["Shop"][] }>("/v1/admin/shops", { query: { q, limit: 8 } }).then((r) => r.items),
        api<{ items: Schemas["User"][] }>("/v1/admin/users", { query: { q, limit: 8 } }).then((r) => r.items),
      ]);
    } catch (err) {
      if (err instanceof ApiError) return <ErrorState message={err.message} />;
      throw err;
    }
  }
  const total = orders.length + shops.length + users.length;

  return (
    <>
      <PageHeader
        overline="Recherche"
        title={q ? `Résultats pour « ${q} »` : "Rechercher"}
        highlight={q ? `« ${q} »` : undefined}
      />
      <form action="/search" role="search" className="mb-6">
        <label htmlFor="q" className="sr-only">
          Rechercher
        </label>
        <input
          id="q"
          name="q"
          defaultValue={q}
          autoFocus
          placeholder="Numéro de commande, boutique, e-mail, téléphone, prénom…"
          className="h-[54px] w-full max-w-[640px] rounded-[14px] bg-surface px-5 text-[16px] outline-none focus:shadow-[inset_0_0_0_2px_var(--color-primary)]"
        />
      </form>
      {!q ? null : total === 0 ? (
        <EmptyState
          title="Aucun résultat"
          message="Vérifiez l'orthographe, ou cherchez par numéro de commande, téléphone ou e-mail."
        />
      ) : (
        <div className="grid grid-cols-3 gap-4 max-[1200px]:grid-cols-1">
          {orders.length > 0 && (
            <Card className="animate-rise">
              <CardTitle icon={<ClipboardList size={18} aria-hidden="true" />}>Commandes</CardTitle>
              <ul className="divide-y divide-border">
                {orders.map((o) => (
                  <li key={o.id} className="py-3">
                    <Link
                      href={`/orders/${o.id}`}
                      className="flex items-center justify-between gap-3 hover:text-primary"
                    >
                      <span className="font-extrabold">#{o.number}</span>
                      <span className="text-text-secondary">{formatXOF(o.total_xof)}</span>
                      <StatusBadge {...statusOf(ORDER_STATUS, o.status)} />
                    </Link>
                  </li>
                ))}
              </ul>
            </Card>
          )}
          {shops.length > 0 && (
            <Card className="animate-rise">
              <CardTitle icon={<Store size={18} aria-hidden="true" />}>Boutiques</CardTitle>
              <ul className="divide-y divide-border">
                {shops.map((s) => (
                  <li key={s.id} className="py-3">
                    <Link href={`/shops/${s.id}`} className="flex items-center gap-3 hover:text-primary">
                      <Avatar name={s.name} tone="imperial" size={34} />
                      <span className="min-w-0 flex-1 truncate font-bold">{s.name}</span>
                      <StatusBadge {...statusOf(SHOP_STATUS, s.status)} />
                    </Link>
                  </li>
                ))}
              </ul>
            </Card>
          )}
          {users.length > 0 && (
            <Card className="animate-rise">
              <CardTitle icon={<Users size={18} aria-hidden="true" />}>Comptes</CardTitle>
              <ul className="divide-y divide-border">
                {users.map((u) => {
                  const driver = u.roles.includes("driver");
                  return (
                    <li key={u.id} className="py-3">
                      <Link
                        href={driver ? `/drivers/${u.id}` : `/users?q=${encodeURIComponent(u.email ?? "")}`}
                        className="flex items-center gap-3 hover:text-primary"
                      >
                        <Avatar
                          name={u.first_name || u.email || "?"}
                          tone={driver ? "cobalt" : "berkeley"}
                          size={34}
                        />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate font-bold">
                            {[u.first_name, u.last_name].filter(Boolean).join(" ") || u.email}
                          </span>
                          <span className="block truncate text-[13px] text-text-muted">
                            {formatPhone(u.phone)} · {u.roles.map((r) => ROLE_LABEL[r] ?? r).join(", ")}
                          </span>
                        </span>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </Card>
          )}
        </div>
      )}
    </>
  );
}
