import { ActionForm } from "@/components/action-form";
import { Card, ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { deleteVisual } from "../../actions";
import { KINDS } from "../../labels";
import { VisualForm } from "../../visual-form";

export const metadata = { title: "Visuel" };

type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ created?: string }> };

export default async function VisualPage({ params, searchParams }: Props) {
  const { id } = await params;
  const { created } = await searchParams;
  let visual: Schemas["PromoVisual"];
  let products: Schemas["Product"][];
  let settings: Schemas["PromoSettings"];
  try {
    [visual, products, settings] = await Promise.all([
      api<Schemas["PromoVisual"]>(`/v1/admin/promo/visuals/${id}`),
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
        overline={`Publicité · ${KINDS[visual.kind]?.label ?? visual.kind}`}
        title={visual.title}
        description={
          created
            ? "Visuel publié : les apps l'affichent dès leur prochain chargement."
            : visual.live
              ? "En diffusion dans les apps."
              : "Pas en diffusion (arrêté ou hors période)."
        }
        actions={
          <ActionForm
            action={deleteVisual}
            hidden={{ id: visual.id }}
            variant="danger"
            label="Supprimer"
            confirm={{
              title: "Supprimer ce visuel ?",
              body: "Il disparaît des apps ; ses statistiques sont conservées.",
            }}
          />
        }
      />
      <Card>
        <VisualForm
          visual={visual}
          products={products.map((p) => ({ id: p.id, name: p.name }))}
          officialURL={settings.official_url}
        />
      </Card>
    </>
  );
}
