import { Card, CardTitle, DefinitionList, ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";

export const metadata = { title: "Coûts de la carte" };

function percent(part: number, total: number): string {
  return total === 0 ? "—" : `${Math.round((part / total) * 100)} %`;
}

export default async function GeoMetricsPage() {
  let m: Schemas["GeoMetrics"];
  try {
    m = await api<Schemas["GeoMetrics"]>("/v1/admin/geo/metrics");
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const t = (k: string) => m.totals[k] ?? 0;

  return (
    <>
      <PageHeader
        overline="Carte"
        title="Les coûts de la carte, sur 30 jours"
        highlight="coûts"
        description="Objectif : plus de 70 % des recherches résolues sans appeler Google."
      />
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardTitle>Recherche de lieux</CardTitle>
          <DefinitionList
            items={[
              ["Recherches", String(t("search_total"))],
              ["Taux de résolution locale", percent(t("search_local"), t("search_total"))],
              ["Appels Google, recherche", String(t("google_autocomplete"))],
              ["Appels Google, détail", String(t("google_details"))],
            ]}
          />
        </Card>
        <Card>
          <CardTitle>Fournisseurs actifs</CardTitle>
          <DefinitionList
            items={[
              ["Itinéraires", m.routing],
              ["Géocodage inverse", m.geocoding],
              ["Recherche de lieux", m.places],
              ["Temps réel", m.redis ? "Redis" : "Mémoire (un seul serveur)"],
              ["Replis à vol d'oiseau", String(t("routing_fallback"))],
              [
                "Cache du géocodage",
                percent(t("reverse_cache_hit"), t("reverse_cache_hit") + t("reverse_cache_miss")),
              ],
            ]}
          />
        </Card>
      </div>
    </>
  );
}
