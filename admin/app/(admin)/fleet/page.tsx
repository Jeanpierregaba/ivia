import { ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError } from "@/lib/api";
import { FleetMap, type FleetDriver } from "./fleet-map";

export const metadata = { title: "Carte de la flotte" };

export default async function FleetPage() {
  let data: { items: FleetDriver[]; generated_at: string };
  try {
    data = await api("/v1/admin/fleet", { query: { hours: 24 } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  return (
    <>
      <PageHeader
        overline="Réseau"
        title="Carte de la flotte en direct"
        highlight="en direct"
        description="Position des livreurs vus ces dernières 24 heures, leur course en cours et leur trajet."
      />
      <FleetMap initial={data.items} generatedAt={data.generated_at} />
    </>
  );
}
