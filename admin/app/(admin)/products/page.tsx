import { Droplets, Star } from "lucide-react";
import Link from "next/link";

import {
  EmptyState,
  ErrorState,
  FilterTabs,
  PageHeader,
  Pagination,
  StatusBadge,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatXOF } from "@/lib/format";
import { BADGES } from "../promo/labels";

export const metadata = { title: "Produits" };

const LIMIT = 30;

type Props = { searchParams: Promise<{ q?: string; offset?: string; shop_id?: string }> };

const STATUS: Record<string, { label: string; tone: "success" | "warning" | "muted" }> = {
  active: { label: "En vente", tone: "success" },
  draft: { label: "Brouillon", tone: "warning" },
  withdrawn: { label: "Retiré", tone: "muted" },
};

export default async function ProductsPage({ searchParams }: Props) {
  const sp = await searchParams;
  const q = sp.q ?? "";
  const offset = Number(sp.offset ?? 0) || 0;
  let page: { items: Schemas["Product"][]; next_offset?: number | null };
  try {
    page = await api("/v1/admin/products", { query: { q, limit: LIMIT, offset, shop_id: sp.shop_id } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  return (
    <>
      <PageHeader
        overline="Marketing"
        title="Produits et mise en avant"
        highlight="mise en avant"
        description="Produits IVI et AWU-IVI d'abord : prix, promotions, badges, rang de mise en avant et stock."
      />
      <FilterTabs
        current={q.toLowerCase() === "ivi" ? "ivi" : q ? "q" : ""}
        tabs={[
          { value: "", label: "Tous (mis en avant d'abord)", href: "/products" },
          { value: "ivi", label: "Gamme IVI", href: "/products?q=ivi" },
        ]}
      />
      <form className="mb-6 flex gap-2" action="/products">
        <input
          name="q"
          defaultValue={q}
          placeholder="Rechercher un produit…"
          className="h-11 w-96 rounded-field border border-border-input bg-surface px-4 outline-none focus:border-2 focus:border-primary"
        />
      </form>
      {page.items.length === 0 ? (
        <EmptyState message="Aucun produit trouvé." />
      ) : (
        <Table head={["Produit", "Prix", "Badges", "Mise en avant", "Stock", "Statut"]}>
          {page.items.map((p) => {
            const st = STATUS[p.status] ?? { label: "Brouillon", tone: "warning" as const };
            return (
              <tr key={p.id}>
                <Td>
                  <Link
                    href={`/products/${p.id}`}
                    className="flex items-center gap-3 font-semibold hover:underline"
                  >
                    {p.images[0] ? (
                      // eslint-disable-next-line @next/next/no-img-element -- image servie par l'API
                      <img src={p.images[0].url} alt="" className="size-12 rounded-card object-cover" />
                    ) : (
                      <span className="grid size-12 place-items-center rounded-card bg-secondary-soft text-tertiary">
                        <Droplets size={20} aria-hidden="true" />
                      </span>
                    )}
                    {p.name}
                  </Link>
                </Td>
                <Td>
                  {p.price_xof === 0 ? (
                    <span className="font-semibold text-warning">À renseigner</span>
                  ) : p.promo_active ? (
                    <>
                      <span className="font-semibold text-primary">{formatXOF(p.effective_price_xof)}</span>{" "}
                      <s className="text-text-muted">{formatXOF(p.price_xof)}</s>
                    </>
                  ) : (
                    formatXOF(p.price_xof)
                  )}
                </Td>
                <Td>
                  <span className="flex flex-wrap gap-1">
                    {p.badges.map((b) => (
                      <span
                        key={b}
                        className="rounded-full bg-primary-soft px-2 py-0.5 text-[12px] font-semibold text-primary"
                      >
                        {BADGES[b] ?? b}
                      </span>
                    ))}
                  </span>
                </Td>
                <Td>
                  {p.featured_rank ? (
                    <span className="inline-flex items-center gap-1 font-semibold text-tertiary">
                      <Star size={14} aria-hidden="true" /> n° {p.featured_rank}
                    </span>
                  ) : (
                    "—"
                  )}
                </Td>
                <Td>{p.stock_mode === "tracked" ? p.stock_quantity : "Non suivi"}</Td>
                <Td>
                  <StatusBadge label={st.label} tone={st.tone} />
                </Td>
              </tr>
            );
          })}
        </Table>
      )}
      <Pagination
        basePath="/products"
        params={{ q, shop_id: sp.shop_id }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
