import { Card, ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { VisualForm } from "../../visual-form";

export const metadata = { title: "Publier un visuel" };

export default async function NewVisualPage() {
  let products: Schemas["Product"][];
  let settings: Schemas["PromoSettings"];
  try {
    [products, settings] = await Promise.all([
      api<{ items: Schemas["Product"][] }>("/v1/admin/products", { query: { limit: 100 } }).then(
        (r) => r.items,
      ),
      api<Schemas["PromoSettings"]>("/v1/admin/promo/settings"),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  return (
    <>
      <PageHeader
        overline="Publicité"
        title="Publier un visuel"
        highlight="visuel"
        description="Affiche, bannière, visuel de bienvenue ou du mois : il part directement dans les apps."
      />
      <Card>
        <VisualForm
          products={products.map((p) => ({ id: p.id, name: p.name }))}
          officialURL={settings.official_url}
        />
      </Card>
    </>
  );
}
