import Link from "next/link";

import { ActionForm } from "@/components/action-form";
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
import { formatDateTime, INCIDENT_KIND } from "@/lib/format";
import { resolveIncident } from "../drivers/actions";

export const metadata = { title: "Signalements livreurs" };

const LIMIT = 20;

type Props = { searchParams: Promise<{ status?: string; offset?: string }> };

export default async function DriverIncidentsPage({ searchParams }: Props) {
  const sp = await searchParams;
  const status = sp.status === "resolved" ? "resolved" : "open";
  const offset = Number(sp.offset ?? 0) || 0;

  let page: { items: Schemas["DriverIncident"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/driver-incidents", { query: { status, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Flotte"
        title="Les signalements des livreurs"
        highlight="signalements"
        description="Colis endommagé, adresse introuvable, code refusé ou accident, envoyés depuis l'app livreur. Un accident est signalé en urgence."
      />
      <FilterTabs
        current={status}
        tabs={[
          { value: "open", label: "À traiter", href: "/driver-incidents?status=open" },
          { value: "resolved", label: "Traités", href: "/driver-incidents?status=resolved" },
        ]}
      />
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucun signalement dans cette liste." />
      ) : (
        <Table head={["Reçu", "Problème", "Livreur", "Message", "Photo et lieu", ""]}>
          {page.items.map((i) => (
            <tr key={i.id}>
              <Td>{formatDateTime(i.created_at)}</Td>
              <Td>
                <StatusBadge
                  label={INCIDENT_KIND[i.kind] ?? i.kind}
                  tone={i.kind === "accident" ? "error" : "warning"}
                />
                {i.mission_type && (
                  <p className="mt-1 text-[12px] text-text-muted">
                    Course {i.mission_type === "pharmacy" ? "pharmacie" : "boutique"}
                  </p>
                )}
              </Td>
              <Td>
                <Link
                  href={`/drivers/${i.driver_id}`}
                  className="font-semibold text-secondary hover:underline"
                >
                  Ouvrir le dossier
                </Link>
              </Td>
              <Td>{i.note || "—"}</Td>
              <Td>
                <div className="flex flex-col gap-1">
                  {i.photo_url ? (
                    // Lien temporaire vers le compartiment privé.
                    <a
                      href={i.photo_url}
                      target="_blank"
                      rel="noreferrer"
                      className="text-secondary hover:underline"
                    >
                      Voir la photo
                    </a>
                  ) : (
                    <span className="text-text-muted">Sans photo</span>
                  )}
                  {i.location ? (
                    <a
                      href={`https://www.google.com/maps?q=${i.location.lat},${i.location.lng}`}
                      target="_blank"
                      rel="noreferrer"
                      className="text-secondary hover:underline"
                    >
                      Voir sur la carte
                    </a>
                  ) : (
                    <span className="text-text-muted">Sans position</span>
                  )}
                </div>
              </Td>
              <Td>
                {i.status === "open" ? (
                  <ActionForm
                    action={resolveIncident}
                    label="Clore"
                    variant="outline"
                    hidden={{ id: i.id }}
                    confirm={{
                      title: "Clore ce signalement ?",
                      body: "Indiquez la suite donnée, gardée au journal.",
                    }}
                    reason={{ label: "Suite donnée", required: true }}
                  />
                ) : (
                  <span className="text-[13px] text-text-secondary">
                    {i.resolution_note} · {formatDateTime(i.resolved_at)}
                  </span>
                )}
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/driver-incidents"
        params={{ status }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
