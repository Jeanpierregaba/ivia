import { Bell } from "lucide-react";

import { ActionForm } from "@/components/action-form";
import { EmptyState, ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError } from "@/lib/api";
import { formatDateTime } from "@/lib/format";
import { markAllRead } from "./actions";

export const metadata = { title: "Notifications" };

type Notification = {
  id: string;
  title: string;
  body: string;
  read_at: string | null;
  created_at: string;
  data: Record<string, string>;
};

// Notifications des admins : boutiques et livreurs à valider, paiements en double, codes bloqués…
export default async function NotificationsPage() {
  let page: { items: Notification[]; unread_count: number };
  try {
    page = await api("/v1/notifications", { query: { app: "admin", limit: 50 } });
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const link = (n: Notification) =>
    n.data.order_id
      ? `/orders/${n.data.order_id}`
      : n.data.shop_id
        ? `/shops/${n.data.shop_id}`
        : n.data.payment_id
          ? "/payments?duplicates=true"
          : null;

  return (
    <>
      <PageHeader
        overline="Plateforme"
        title="Notifications"
        description={page.unread_count ? `${page.unread_count} non lue(s).` : "Tout est lu."}
        actions={
          page.unread_count > 0 ? (
            <ActionForm action={markAllRead} label="Tout marquer comme lu" variant="outline" />
          ) : undefined
        }
      />
      {page.items.length === 0 ? (
        <EmptyState title="Aucune notification" message="Les alertes de la plateforme apparaîtront ici." />
      ) : (
        <ul className="space-y-2">
          {page.items.map((n) => {
            const href = link(n);
            const body = (
              <div className="flex items-start gap-4">
                <span
                  className={`mt-1 grid size-10 shrink-0 place-items-center rounded-full ${n.read_at ? "bg-background text-text-muted" : "bg-primary-soft text-primary"}`}
                >
                  <Bell size={18} aria-hidden="true" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className={n.read_at ? "font-semibold" : "font-extrabold"}>{n.title}</p>
                  <p className="text-text-secondary">{n.body}</p>
                  <p className="mt-1 text-[13px] text-text-muted">{formatDateTime(n.created_at)}</p>
                </div>
                {!n.read_at && (
                  <span className="mt-2 size-2.5 rounded-full bg-primary" aria-label="Non lue" />
                )}
              </div>
            );
            return (
              <li key={n.id} className="animate-rise rounded-[18px] bg-surface p-5">
                {href ? (
                  <a href={href} className="block hover:opacity-80">
                    {body}
                  </a>
                ) : (
                  body
                )}
              </li>
            );
          })}
        </ul>
      )}
    </>
  );
}
