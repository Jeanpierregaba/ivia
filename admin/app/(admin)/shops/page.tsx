import { ActionForm } from "@/components/action-form";
import {
  Avatar,
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
import { formatDateTime, formatPhone, SHOP_STATUS, statusOf } from "@/lib/format";
import { reviewShop } from "./actions";

export const metadata = { title: "Boutiques" };

const LIMIT = 20;
const TABS = [
  { value: "pending_review", label: "À valider" },
  { value: "published", label: "Publiées" },
  { value: "suspended", label: "Suspendues" },
  { value: "rejected", label: "Refusées" },
  { value: "", label: "Toutes" },
];

type Props = { searchParams: Promise<{ status?: string; offset?: string }> };

export default async function ShopsPage({ searchParams }: Props) {
  const sp = await searchParams;
  const status = sp.status ?? "pending_review";
  const offset = Number(sp.offset ?? 0) || 0;

  let page: { items: Schemas["Shop"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/shops", { query: { status, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Marchands"
        title="Les boutiques de la plateforme"
        highlight="boutiques"
        description="Une boutique n'est visible des acheteurs qu'une fois publiée."
      />
      <FilterTabs current={status} tabs={TABS.map((t) => ({ ...t, href: `/shops?status=${t.value}` }))} />
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucune boutique dans cette liste pour le moment." />
      ) : (
        <Table head={["Boutique", "Catégorie", "Contact", "Statut", "Créée le", "Actions"]}>
          {page.items.map((s) => (
            <tr key={s.id}>
              <Td>
                <div className="flex items-center gap-3">
                  <Avatar name={s.name} tone="imperial" />
                  <div className="min-w-0">
                    <p className="font-semibold">{s.name}</p>
                    <p className="text-[13px] text-text-muted">
                      {s.address_text}
                      {s.neighborhood_name && ` · ${s.neighborhood_name}`}
                    </p>
                    {s.status_reason && (
                      <p className="text-[13px] text-text-secondary">Motif : {s.status_reason}</p>
                    )}
                  </div>
                </div>
              </Td>
              <Td>{s.category_name || "—"}</Td>
              <Td>{formatPhone(s.phone)}</Td>
              <Td>
                <StatusBadge {...statusOf(SHOP_STATUS, s.status)} />
              </Td>
              <Td>{formatDateTime(s.created_at)}</Td>
              <Td>
                <ShopActions shop={s} />
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/shops"
        params={{ status }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}

function ShopActions({ shop }: { shop: Schemas["Shop"] }) {
  const hidden = (decision: string) => ({ id: shop.id, decision });
  return (
    <div className="flex flex-wrap gap-2">
      {(shop.status === "pending_review" || shop.status === "rejected") && (
        <ActionForm
          action={reviewShop}
          label="Publier"
          hidden={hidden("approve")}
          confirm={{
            title: `Publier « ${shop.name} » ?`,
            body: "La boutique devient visible des acheteurs et peut vendre.",
          }}
        />
      )}
      {shop.status === "pending_review" && (
        <ActionForm
          action={reviewShop}
          label="Refuser"
          variant="outline"
          hidden={hidden("reject")}
          confirm={{ title: `Refuser « ${shop.name} » ?`, body: "Le motif est communiqué au marchand." }}
          reason={{ label: "Motif du refus", required: true }}
        />
      )}
      {shop.status === "published" && (
        <ActionForm
          action={reviewShop}
          label="Suspendre"
          variant="danger"
          hidden={hidden("suspend")}
          confirm={{
            title: `Suspendre « ${shop.name} » ?`,
            body: "La boutique disparaît des recherches et le marchand perd l'accès aux commandes dès maintenant.",
          }}
          reason={{ label: "Motif de la suspension", required: true }}
        />
      )}
      {shop.status === "suspended" && (
        <ActionForm
          action={reviewShop}
          label="Rétablir"
          variant="outline"
          hidden={hidden("reinstate")}
          confirm={{
            title: `Rétablir « ${shop.name} » ?`,
            body: "La boutique redevient visible des acheteurs.",
          }}
        />
      )}
    </div>
  );
}
