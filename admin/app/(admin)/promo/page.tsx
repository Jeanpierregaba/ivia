import {
  BarChart3,
  Eye,
  Megaphone,
  MousePointerClick,
  Plus,
  Settings2,
  ShoppingBag,
  XCircle,
} from "lucide-react";
import Link from "next/link";

import { ActionForm } from "@/components/action-form";
import { LiveRefresh } from "@/components/live";
import {
  buttonClass,
  Card,
  CardTitle,
  EmptyState,
  ErrorState,
  PageHeader,
  StatusBadge,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatXOF, frDate } from "@/lib/format";
import { toggleVisual } from "./actions";
import { KINDS, PLACEMENTS, pct } from "./labels";
import { PromoSettingsForm } from "./settings-form";

export const metadata = { title: "Publicité" };

export default async function PromoPage() {
  let visuals: Schemas["PromoVisual"][];
  let stats: Schemas["PromoStats"];
  let settings: Schemas["PromoSettings"];
  try {
    [visuals, stats, settings] = await Promise.all([
      api<{ items: Schemas["PromoVisual"][] }>("/v1/admin/promo/visuals").then((r) => r.items),
      api<Schemas["PromoStats"]>("/v1/admin/promo/stats"),
      api<Schemas["PromoSettings"]>("/v1/admin/promo/settings"),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const perVisual = new Map(stats.visuals.map((v) => [v.visual_id, v]));
  const clicks = stats.order_clicks + stats.product_clicks + stats.site_clicks;
  const maxDay = Math.max(1, ...stats.per_day.map((d) => d.impressions ?? 0));

  return (
    <>
      <LiveRefresh generatedAt={new Date().toISOString()} />
      <PageHeader
        overline="Marketing"
        title="Publicité dans les apps"
        highlight="Publicité"
        description={`Visuels IVI et partenaires diffusés dans les apps : bannières, fenêtres, interstitiels. Statistiques du ${frDate(stats.from)} au ${frDate(stats.to)}.`}
        actions={
          <Link href="/promo/visuals/new" className={buttonClass("imperial")}>
            <Plus size={18} aria-hidden="true" /> Publier un visuel
          </Link>
        }
      />

      {!settings.enabled && (
        <p className="mb-6 rounded-field bg-primary-soft px-4 py-3 font-semibold text-error">
          La publicité est coupée : aucun visuel n&apos;est diffusé (réglages en bas de page).
        </p>
      )}

      <div className="mb-8 grid grid-cols-2 md:grid-cols-3 2xl:grid-cols-5 gap-4">
        {[
          {
            icon: Eye,
            label: "Affichages",
            value: stats.impressions.toLocaleString("fr-FR"),
            sub: `${stats.sessions} sessions`,
          },
          {
            icon: MousePointerClick,
            label: "Clics",
            value: clicks.toLocaleString("fr-FR"),
            sub: `Taux de clic ${pct(stats.ctr_pct)}`,
          },
          {
            icon: ShoppingBag,
            label: "Commandes après clic",
            value: stats.orders.toLocaleString("fr-FR"),
            sub: `Conversion ${pct(stats.conversion_pct)}`,
          },
          {
            icon: Megaphone,
            label: "Vers le site officiel",
            value: stats.site_clicks.toLocaleString("fr-FR"),
            sub: "Clics « Visiter le site »",
          },
          {
            icon: XCircle,
            label: "Fermetures",
            value: stats.dismissals.toLocaleString("fr-FR"),
            sub: "Fenêtres fermées",
          },
        ].map((k, i) => (
          <div
            key={k.label}
            className="tile-in rounded-field bg-surface p-5"
            style={{ animationDelay: `${i * 60}ms` }}
          >
            <p className="flex items-center gap-2 text-[13px] font-semibold text-text-secondary">
              <k.icon size={16} aria-hidden="true" className="text-secondary" /> {k.label}
            </p>
            <p className="mt-2 text-[24px] font-bold leading-8 tracking-[-0.02em]">{k.value}</p>
            <p className="mt-1 text-[13px] text-text-muted">{k.sub}</p>
          </div>
        ))}
      </div>

      <Card className="mb-8">
        <CardTitle icon={<BarChart3 size={18} />}>Affichages et clics par jour</CardTitle>
        {stats.per_day.length === 0 ? (
          <EmptyState message="Aucun affichage enregistré sur la période." />
        ) : (
          <div className="flex h-40 items-end gap-1.5" role="img" aria-label="Affichages et clics par jour">
            {stats.per_day.map((d) => (
              <div
                key={d.day}
                className="flex flex-1 flex-col items-center gap-1"
                title={`${frDate(d.day)} : ${d.impressions} affichages, ${d.clicks} clics`}
              >
                <div className="flex w-full items-end gap-0.5" style={{ height: 128 }}>
                  <span
                    className="grow w-1/2 rounded-t bg-secondary"
                    style={{ height: `${((d.impressions ?? 0) / maxDay) * 100}%` }}
                  />
                  <span
                    className="grow w-1/2 rounded-t bg-primary"
                    style={{ height: `${((d.clicks ?? 0) / maxDay) * 100}%` }}
                  />
                </div>
                <span className="text-[11px] text-text-muted">{(d.day ?? "").slice(8, 10)}</span>
              </div>
            ))}
          </div>
        )}
      </Card>

      <h2 className="mb-4 text-[18px] font-bold">Visuels publiés</h2>
      {visuals.length === 0 ? (
        <EmptyState
          title="Aucun visuel"
          message="Publiez une affiche, une bannière ou un visuel de bienvenue."
        />
      ) : (
        <div className="mb-10 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {visuals.map((v, i) => {
            const s = perVisual.get(v.id);
            return (
              <article
                key={v.id}
                className="rise overflow-hidden rounded-field bg-surface"
                style={{ animationDelay: `${i * 50}ms` }}
              >
                <Link href={`/promo/visuals/${v.id}`} className="block aspect-[16/9] bg-background-alt">
                  {/* eslint-disable-next-line @next/next/no-img-element -- image servie par l'API */}
                  <img src={v.image_url} alt="" className="size-full object-cover" />
                </Link>
                <div className="space-y-3 p-5">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-[12px] font-semibold uppercase tracking-[0.08em] text-secondary">
                        {KINDS[v.kind]?.label ?? v.kind} · priorité {v.priority}
                      </p>
                      <h3 className="mt-1 text-[15px] font-bold leading-6">{v.title}</h3>
                    </div>
                    <StatusBadge
                      label={v.live ? "En diffusion" : v.is_active ? "Programmé" : "Arrêté"}
                      tone={v.live ? "success" : v.is_active ? "info" : "muted"}
                    />
                  </div>
                  <p className="text-[13px] text-text-muted">
                    {v.placements.map((p) => PLACEMENTS[p] ?? p).join(" · ")}
                    {v.ends_at && ` — jusqu'au ${frDate(v.ends_at)}`}
                  </p>
                  <p className="text-[13px] text-text-secondary">
                    {(s?.impressions ?? 0).toLocaleString("fr-FR")} affichages ·{" "}
                    {(s?.clicks ?? 0).toLocaleString("fr-FR")} clics · {pct(s?.ctr_pct ?? 0)}
                  </p>
                  <div className="flex gap-2">
                    <Link href={`/promo/visuals/${v.id}`} className={buttonClass("outline")}>
                      Modifier
                    </Link>
                    <ActionForm
                      action={toggleVisual}
                      hidden={{ id: v.id }}
                      variant={v.is_active ? "ghost" : "primary"}
                      label={v.is_active ? "Arrêter" : "Diffuser"}
                    />
                  </div>
                </div>
              </article>
            );
          })}
        </div>
      )}

      <h2 className="mb-4 text-[18px] font-bold">Produits promus</h2>
      {stats.products.length === 0 ? (
        <EmptyState message="Aucun produit mis en avant ou promu pour le moment." />
      ) : (
        <div className="mb-10">
          <Table
            head={[
              "Produit",
              "Rang",
              "Affichages",
              "Fiches vues",
              "Clics « Commander »",
              "Commandes payées",
              "Unités",
              "Chiffre d'affaires",
            ]}
          >
            {stats.products.map((p) => (
              <tr key={p.product_id}>
                <Td>
                  <Link
                    className="font-semibold text-secondary hover:underline"
                    href={`/products/${p.product_id}`}
                  >
                    {p.name || "Produit supprimé"}
                  </Link>
                </Td>
                <Td>{p.featured_rank ?? "—"}</Td>
                <Td>{p.impressions ?? 0}</Td>
                <Td>{p.views ?? 0}</Td>
                <Td>{p.order_clicks ?? 0}</Td>
                <Td>{p.paid_orders ?? 0}</Td>
                <Td>{p.units_sold ?? 0}</Td>
                <Td>{formatXOF(p.revenue_xof ?? 0)}</Td>
              </tr>
            ))}
          </Table>
        </div>
      )}

      <Card>
        <CardTitle icon={<Settings2 size={18} />}>Réglages de diffusion</CardTitle>
        <PromoSettingsForm settings={settings} />
      </Card>
    </>
  );
}
