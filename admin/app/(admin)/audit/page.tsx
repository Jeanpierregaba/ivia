import { EmptyState, ErrorState, PageHeader, Pagination, Table, Td } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { AUDIT_ACTION, formatDateTime } from "@/lib/format";

export const metadata = { title: "Journal des actions" };

const LIMIT = 50;

export default async function AuditPage({ searchParams }: { searchParams: Promise<{ offset?: string }> }) {
  const offset = Number((await searchParams).offset ?? 0) || 0;
  let page: { items: Schemas["AuditRecord"][]; next_offset: number | null };
  try {
    page = await api("/v1/admin/audit-log", { query: { limit: LIMIT, offset } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  return (
    <>
      <PageHeader
        overline="Traçabilité"
        title="Journal des actions"
        highlight="actions"
        description="Toutes les actions des admins, en ajout seul : rien n'y est modifiable."
      />
      {page.items.length === 0 ? (
        <EmptyState title="Journal vide" message="Aucune action d'admin enregistrée pour l'instant." />
      ) : (
        <Table head={["Date", "Action", "Cible", "Admin", "Motif"]}>
          {page.items.map((a) => (
            <tr key={a.id}>
              <Td className="whitespace-nowrap">{formatDateTime(a.created_at)}</Td>
              <Td>
                <p className="font-semibold">{AUDIT_ACTION[a.action] ?? a.action}</p>
                <p className="font-mono text-[12px] text-text-muted">{a.action}</p>
              </Td>
              <Td className="text-[13px]">
                {a.target_type} <span className="text-text-muted">{a.target_id}</span>
              </Td>
              <Td className="text-[13px] text-text-muted">{a.admin_id ?? "système"}</Td>
              <Td>{a.reason || "—"}</Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination basePath="/audit" params={{}} offset={offset} nextOffset={page.next_offset} limit={LIMIT} />
    </>
  );
}
