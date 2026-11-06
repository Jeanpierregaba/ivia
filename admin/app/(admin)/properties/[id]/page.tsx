import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ActionForm } from "@/components/action-form";
import { Card, ErrorState, PageHeader, StatusBadge } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { setPropertyActive } from "../actions";
import { PropertyForm } from "../property-form";

export const metadata = { title: "Annonce" };

export default async function PropertyPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  let p: Schemas["AdminProperty"];
  try {
    p = await api<Schemas["AdminProperty"]>(`/v1/admin/properties/${encodeURIComponent(id)}`);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <Link
        href="/properties"
        className="mb-4 inline-flex items-center gap-1 text-[13px] font-semibold text-secondary hover:underline"
      >
        <ChevronLeft size={16} aria-hidden="true" /> Immobilier
      </Link>
      <PageHeader overline="Réseau" title={p.title} />
      <div className="mb-4 flex items-center gap-3">
        <StatusBadge label={p.is_active ? "Publiée" : "Retirée"} tone={p.is_active ? "success" : "muted"} />
        {p.is_active ? (
          <ActionForm
            action={setPropertyActive}
            label="Retirer de l'app"
            variant="danger"
            hidden={{ id: p.id, is_active: "false" }}
            confirm={{ title: `Retirer « ${p.title} » ?`, body: "L'annonce disparaît aussitôt de l'app acheteur." }}
            reason={{ label: "Motif du retrait", required: true }}
          />
        ) : (
          <ActionForm
            action={setPropertyActive}
            label="Publier"
            hidden={{ id: p.id, is_active: "true" }}
            confirm={{ title: `Publier « ${p.title} » ?`, body: "L'annonce redevient visible dans l'app acheteur." }}
          />
        )}
      </div>
      <Card>
        <PropertyForm property={p} />
      </Card>
    </>
  );
}
