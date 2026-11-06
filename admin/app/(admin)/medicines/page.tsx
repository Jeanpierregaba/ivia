import { Plus, Search } from "lucide-react";

import { ActionForm } from "@/components/action-form";
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
import { createMedicine, toggleMedicine } from "../pharmacies/actions";

export const metadata = { title: "Médicaments" };

const LIMIT = 30;

export default async function MedicinesPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; offset?: string }>;
}) {
  const sp = await searchParams;
  const q = sp.q?.trim() || undefined;
  const offset = Number(sp.offset ?? 0) || 0;
  let page: { items: Schemas["Medicine"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/medicines", { query: { q, limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Santé"
        title="La base des médicaments"
        highlight="médicaments"
        description="Elle alimente l'autocomplétion de l'alerte médicament. Le patient peut toujours saisir un nom libre."
      />
      <Card className="mb-4">
        <CardTitle icon={<Plus size={18} aria-hidden="true" />}>Ajouter un médicament</CardTitle>
        <ServerForm action={createMedicine} submitLabel="Ajouter" variant="imperial">
          <div className="grid grid-cols-4 gap-3">
            <Field label="Nom">
              <input name="name" required maxLength={120} className={fieldClass} placeholder="Paracétamol" />
            </Field>
            <Field label="Dosage">
              <input name="dosage" maxLength={60} className={fieldClass} placeholder="500 mg" />
            </Field>
            <Field label="Forme">
              <input name="form" maxLength={60} className={fieldClass} placeholder="Comprimé" />
            </Field>
            <Field label="Principe actif">
              <input name="active_ingredient" maxLength={120} className={fieldClass} />
            </Field>
          </div>
        </ServerForm>
      </Card>
      <form action="/medicines" role="search" className="relative mb-4 w-80">
        <Search size={16} aria-hidden="true" className="absolute left-3 top-1/2 -translate-y-1/2 text-text-muted" />
        <input
          name="q"
          defaultValue={q}
          aria-label="Rechercher un médicament"
          placeholder="Rechercher un médicament"
          className={`${fieldClass} pl-9`}
        />
      </form>
      {page.items.length === 0 ? (
        <EmptyState title="Rien à afficher" message="Aucun médicament ne correspond." />
      ) : (
        <Table head={["Médicament", "Forme", "Principe actif", "État", ""]}>
          {page.items.map((m) => (
            <tr key={m.id}>
              <Td>
                <span className="font-semibold">{m.label}</span>
              </Td>
              <Td>{m.form || "—"}</Td>
              <Td>{m.active_ingredient || "—"}</Td>
              <Td>
                <StatusBadge
                  label={m.is_active ? "Proposé" : "Retiré"}
                  tone={m.is_active ? "success" : "muted"}
                />
              </Td>
              <Td>
                <ActionForm
                  action={toggleMedicine}
                  label={m.is_active ? "Retirer" : "Réactiver"}
                  variant="outline"
                  hidden={{
                    id: m.id,
                    name: m.name,
                    dosage: m.dosage,
                    form: m.form,
                    active_ingredient: m.active_ingredient,
                    is_active: String(!m.is_active),
                  }}
                />
              </Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination basePath="/medicines" params={{ q }} offset={offset} nextOffset={page.next_offset} limit={LIMIT} />
    </>
  );
}
