import { MessageSquareHeart, Star, Truck } from "lucide-react";
import Link from "next/link";

import {
  Card,
  CardTitle,
  EmptyState,
  ErrorState,
  FilterTabs,
  PageHeader,
  Pagination,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime } from "@/lib/format";

export const metadata = { title: "Avis" };

const LIMIT = 30;
const APP: Record<string, string> = {
  buyer: "ivia",
  seller: "Ivia Business",
  driver: "Ivia Driver",
  pharmacy: "ivia Pharmacie",
};
const TAG: Record<string, string> = {
  rapide: "Rapide",
  aimable: "Aimable",
  soigneux: "Soigneux",
  ponctuel: "Ponctuel",
  professionnel: "Professionnel",
  en_retard: "En retard",
  colis_abime: "Colis abîmé",
  impoli: "Impoli",
  difficile_a_joindre: "Difficile à joindre",
};

function Stars({ n }: { n: number }) {
  return (
    <span className="inline-flex" aria-label={`${n} sur 5`}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Star
          key={i}
          size={15}
          aria-hidden="true"
          className={i <= n ? "fill-[#F5B301] text-[#F5B301]" : "text-border-input"}
        />
      ))}
    </span>
  );
}

const avg = (v: number) => v.toLocaleString("fr-FR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

type Props = { searchParams: Promise<{ tab?: string; offset?: string }> };

export default async function RatingsPage({ searchParams }: Props) {
  const sp = await searchParams;
  const tab = sp.tab === "app" ? "app" : "delivery";
  const offset = Number(sp.offset ?? 0) || 0;

  type List<T> = { items: T[]; next_offset?: number | null };
  let scores: Schemas["RatingScores"];
  let deliveries: List<Schemas["DeliveryRating"]> | null = null;
  let feedback: List<Schemas["AppFeedback"]> | null = null;
  try {
    [scores, deliveries, feedback] = await Promise.all([
      api<Schemas["RatingScores"]>("/v1/admin/rating-scores"),
      tab === "delivery"
        ? api<List<Schemas["DeliveryRating"]>>("/v1/admin/ratings", { query: { limit: LIMIT, offset } })
        : null,
      tab === "app"
        ? api<List<Schemas["AppFeedback"]>>("/v1/admin/app-feedback", { query: { limit: LIMIT, offset } })
        : null,
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const drivers = scores.drivers ?? [];
  const apps = scores.apps ?? [];
  const page = tab === "app" ? feedback : deliveries;

  return (
    <>
      <PageHeader
        overline="Qualité"
        title="Avis des clients et des marchands"
        highlight="Avis"
        description="Notes des livreurs après chaque livraison et avis sur les applications."
      />

      <div className="mb-6 grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <Card>
          <CardTitle icon={<Truck size={18} aria-hidden="true" />}>Livreurs les plus notés</CardTitle>
          {drivers.length === 0 ? (
            <p className="text-text-secondary">Aucune note pour le moment.</p>
          ) : (
            <ul className="divide-y divide-border">
              {drivers.slice(0, 8).map((d) => (
                <li key={d.driver_id} className="flex flex-wrap items-center justify-between gap-3 py-2.5">
                  <Link href={`/drivers/${d.driver_id}`} className="font-bold hover:text-primary">
                    {d.driver_name || "Livreur"}
                  </Link>
                  <span className="flex items-center gap-3 text-[13px] text-text-secondary">
                    <Stars n={Math.round(d.average ?? 0)} />
                    <strong className="text-text">{avg(d.average ?? 0)}</strong>
                    {d.ratings} avis
                    {(d.low ?? 0) > 0 && (
                      <span className="font-semibold text-error">{d.low} mauvaise(s)</span>
                    )}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card>
          <CardTitle icon={<MessageSquareHeart size={18} aria-hidden="true" />}>
            Notes des applications
          </CardTitle>
          {apps.length === 0 ? (
            <p className="text-text-secondary">Aucun avis pour le moment.</p>
          ) : (
            <ul className="space-y-3">
              {apps.map((a) => (
                <li key={a.app} className="flex items-center justify-between gap-3">
                  <span className="font-semibold">{APP[a.app ?? ""] ?? a.app}</span>
                  <span className="flex items-center gap-2 text-[13px] text-text-secondary">
                    <Stars n={Math.round(a.average ?? 0)} />
                    <strong className="text-text">{avg(a.average ?? 0)}</strong> · {a.ratings} avis
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <FilterTabs
        current={tab}
        tabs={[
          { value: "delivery", label: "Livraisons", href: "/ratings" },
          { value: "app", label: "Applications", href: "/ratings?tab=app" },
        ]}
      />

      {!page || page.items.length === 0 ? (
        <EmptyState title="Aucun avis" message="Les avis s'afficheront ici dès les premières notes." />
      ) : tab === "delivery" ? (
        <Table head={["Date", "Livreur", "Note", "Par", "Commentaire", "Commande"]}>
          {(deliveries?.items ?? []).map((r) => (
            <tr key={r.id}>
              <Td className="whitespace-nowrap text-text-secondary">{formatDateTime(r.created_at)}</Td>
              <Td className="font-semibold">{r.driver_name || "—"}</Td>
              <Td>
                <Stars n={r.stars ?? 0} />
              </Td>
              <Td>{r.rater_role === "seller" ? "Marchand" : `Client ${r.rater_name ?? ""}`}</Td>
              <Td className="max-w-[360px]">
                {(r.tags ?? []).length > 0 && (
                  <span className="mb-1 flex flex-wrap gap-1">
                    {(r.tags ?? []).map((t) => (
                      <span
                        key={t}
                        className="rounded-full bg-background px-2 py-0.5 text-[12px] font-semibold"
                      >
                        {TAG[t] ?? t}
                      </span>
                    ))}
                  </span>
                )}
                <span className="text-text-secondary">{r.comment || ""}</span>
              </Td>
              <Td>
                <Link href={`/orders/${r.order_id}`} className="font-semibold text-secondary hover:underline">
                  {r.order_reference || "Voir"}
                </Link>
              </Td>
            </tr>
          ))}
        </Table>
      ) : (
        <Table head={["Date", "Application", "Note", "Par", "Commentaire"]}>
          {(feedback?.items ?? []).map((f) => (
            <tr key={f.id}>
              <Td className="whitespace-nowrap text-text-secondary">{formatDateTime(f.created_at)}</Td>
              <Td className="font-semibold">{APP[f.app ?? ""] ?? f.app}</Td>
              <Td>
                <Stars n={f.stars ?? 0} />
              </Td>
              <Td>{f.user_name || "—"}</Td>
              <Td className="max-w-[420px] text-text-secondary">{f.comment || ""}</Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/ratings"
        params={{ tab: tab === "app" ? "app" : undefined }}
        offset={offset}
        nextOffset={page?.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
