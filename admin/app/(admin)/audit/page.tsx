import { EmptyState, ErrorState, FilterTabs, PageHeader, Pagination, Table, Td } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { AUDIT_ACTION, formatDateTime } from "@/lib/format";

export const metadata = { title: "Journal des actions" };

const LIMIT = 50;

type Props = { searchParams: Promise<{ offset?: string; admin_id?: string }> };

export default async function AuditPage({ searchParams }: Props) {
  const sp = await searchParams;
  const offset = Number(sp.offset ?? 0) || 0;
  const adminId = sp.admin_id || undefined;
  let page: { items: Schemas["AuditRecord"][]; next_offset: number | null };
  let admins: Schemas["AdminAccount"][];
  try {
    [page, admins] = await Promise.all([
      api<{ items: Schemas["AuditRecord"][]; next_offset: number | null }>("/v1/admin/audit-log", {
        query: { limit: LIMIT, offset, admin_id: adminId },
      }),
      api<{ items: Schemas["AdminAccount"][] }>("/v1/admin/admins").then((r) => r.items),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }

  const names = new Map(
    admins.map((a) => [
      a.id,
      `${[a.first_name, a.last_name].filter(Boolean).join(" ") || a.email} (${a.role_label})`,
    ]),
  );

  return (
    <>
      <PageHeader
        overline="Traçabilité"
        title="Journal des actions"
        highlight="actions"
        description="Toutes les actions des admins, en ajout seul : rien n'y est modifiable."
      />
      <FilterTabs
        current={adminId ?? ""}
        tabs={[
          { value: "", label: "Tous les admins", href: "/audit" },
          ...admins.map((a) => ({
            value: a.id,
            label: `${[a.first_name, a.last_name].filter(Boolean).join(" ") || a.email} · ${a.role_label}`,
            href: `/audit?admin_id=${a.id}`,
          })),
        ]}
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
              <Td className="text-[13px]">
                {a.admin_id
                  ? (names.get(a.admin_id) ?? <span className="text-text-muted">ancien admin</span>)
                  : "système"}
              </Td>
              <Td>{a.reason || "—"}</Td>
            </tr>
          ))}
        </Table>
      )}
      <Pagination
        basePath="/audit"
        params={{ admin_id: adminId }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
