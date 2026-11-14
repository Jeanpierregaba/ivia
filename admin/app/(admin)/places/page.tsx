import { MapPin, Search } from "lucide-react";

import { ServerForm } from "@/components/server-form";
import {
  Card,
  CardTitle,
  EmptyState,
  ErrorState,
  Field,
  fieldClass,
  PageHeader,
  Pagination,
  StatusBadge,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { savePlace } from "./actions";

export const metadata = { title: "Lieux" };

const LIMIT = 30;
const SOURCE: Record<string, string> = {
  ivia: "Ivia",
  osm: "OpenStreetMap",
  google: "Appris (Google)",
  user: "Utilisateur",
};

export default async function PlacesPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; offset?: string }>;
}) {
  const sp = await searchParams;
  const q = sp.q?.trim() || undefined;
  const offset = Number(sp.offset ?? 0) || 0;
  let page: { items: Schemas["AdminPlace"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/places", { query: { q, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Carte"
        title="Les lieux connus d'Ivia"
        highlight="lieux"
        description="Marchés, gares, hôtels, pharmacies : la recherche les propose d'abord, avant tout appel à Google."
      />
      <Card className="mb-4">
        <CardTitle icon={<MapPin size={18} aria-hidden="true" />}>Ajouter un lieu</CardTitle>
        <ServerForm action={savePlace} submitLabel="Ajouter" variant="imperial">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <Field label="Nom">
              <input name="name" required maxLength={160} className={fieldClass} />
            </Field>
            <Field label="Catégorie" hint="market, station, hotel, pharmacy…">
              <input name="category" maxLength={60} className={fieldClass} />
            </Field>
            <Field label="Noms locaux" hint="Séparés par des virgules">
              <input name="aliases" className={fieldClass} />
            </Field>
            <Field label="Adresse">
              <input name="address" maxLength={300} className={fieldClass} />
            </Field>
            <Field label="Latitude" hint="Ex. 6,1319">
              <input name="lat" inputMode="decimal" required className={fieldClass} />
            </Field>
            <Field label="Longitude" hint="Ex. 1,2228">
              <input name="lng" inputMode="decimal" required className={fieldClass} />
            </Field>
          </div>
        </ServerForm>
      </Card>
      <form action="/places" role="search" className="relative mb-4 w-80">
        <Search
          size={16}
          aria-hidden="true"
          className="absolute left-3 top-1/2 -translate-y-1/2 text-text-muted"
        />
        <input
          name="q"
          defaultValue={q}
          aria-label="Rechercher un lieu"
          placeholder="Rechercher un lieu"
          className={`${fieldClass} pl-9`}
        />
      </form>
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucun lieu ne correspond." />
      ) : (
        <Table head={["Lieu", "Catégorie", "Source", "Utilisations", "Position", "État"]}>
          {page.items.map((p) => (
            <tr key={p.id}>
              <Td>
                <p className="font-semibold">{p.name}</p>
                <p className="text-[13px] text-text-muted">{p.address || p.aliases.join(", ")}</p>
              </Td>
              <Td>{p.category || "—"}</Td>
              <Td>{SOURCE[p.source] ?? p.source}</Td>
              <Td>{p.usage_count}</Td>
              <Td>
                <a
                  href={`https://www.openstreetmap.org/?mlat=${p.location.lat}&mlon=${p.location.lng}#map=17/${p.location.lat}/${p.location.lng}`}
                  target="_blank"
                  rel="noreferrer"
                  className="font-semibold text-secondary hover:underline"
                >
                  Voir
                </a>
              </Td>
              <Td>
                <StatusBadge
                  label={p.is_active ? "Proposé" : "Retiré"}
                  tone={p.is_active ? "success" : "muted"}
                />
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/places"
        params={{ q }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
