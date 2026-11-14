import { ChevronRight, Plus } from "lucide-react";
import Link from "next/link";

import {
  buttonClass,
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
import { formatPhone, formatXOF, PROPERTY_KIND, PROPERTY_TYPE } from "@/lib/format";

export const metadata = { title: "Immobilier" };

const LIMIT = 20;
const TABS = [
  { value: "", label: "Toutes" },
  { value: "active", label: "Publiées" },
  { value: "withdrawn", label: "Retirées" },
];

export default async function PropertiesPage({
  searchParams,
}: {
  searchParams: Promise<{ state?: string; offset?: string }>;
}) {
  const sp = await searchParams;
  const state = sp.state || undefined;
  const offset = Number(sp.offset ?? 0) || 0;
  let page: { items: Schemas["AdminProperty"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/properties", { query: { state, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Réseau"
        title="Les annonces immobilières"
        highlight="annonces"
        description="Biens à vendre ou à louer affichés dans l'app acheteur."
      />
      <div className="mb-4 flex items-center justify-between gap-3">
        <FilterTabs
          current={state ?? ""}
          tabs={TABS.map((t) => ({
            value: t.value,
            label: t.label,
            href: t.value ? `/properties?state=${t.value}` : "/properties",
          }))}
        />
        <Link href="/properties/new" className={buttonClass("imperial", "inline-flex items-center gap-2")}>
          <Plus size={16} aria-hidden="true" /> Nouvelle annonce
        </Link>
      </div>
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucune annonce dans cette liste." />
      ) : (
        <Table head={["Bien", "Quartier", "Prix", "Contact", "État", ""]}>
          {page.items.map((p) => (
            <tr key={p.id}>
              <Td>
                <div className="flex items-center gap-3">
                  {p.photo_urls[0] && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={p.photo_urls[0]} alt="" className="size-12 rounded-card object-cover" />
                  )}
                  <div>
                    <p className="font-semibold">{p.title}</p>
                    <p className="text-[13px] text-text-muted">
                      {PROPERTY_TYPE[p.property_type] ?? p.property_type} · {PROPERTY_KIND[p.kind] ?? p.kind}
                    </p>
                  </div>
                </div>
              </Td>
              <Td>{p.neighborhood}</Td>
              <Td>
                {formatXOF(p.price_xof)}
                {p.kind === "rent" && " / mois"}
              </Td>
              <Td>{formatPhone(p.contact_phone)}</Td>
              <Td>
                <StatusBadge
                  label={p.is_active ? "Publiée" : "Retirée"}
                  tone={p.is_active ? "success" : "muted"}
                />
              </Td>
              <Td>
                <Link
                  href={`/properties/${p.id}`}
                  className="inline-flex items-center gap-1 font-semibold text-secondary hover:underline"
                >
                  Modifier <ChevronRight size={16} aria-hidden="true" />
                </Link>
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/properties"
        params={{ state }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
