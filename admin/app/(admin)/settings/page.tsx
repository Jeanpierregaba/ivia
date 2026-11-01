import { Card, ErrorState, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime } from "@/lib/format";
import { SettingsForm } from "./settings-form";

export const metadata = { title: "Paramètres" };

export default async function SettingsPage() {
  let s: Schemas["Settings"];
  try {
    s = await api<Schemas["Settings"]>("/v1/admin/settings");
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  return (
    <>
      <PageHeader
        title="Paramètres"
        description={`Dernière modification : ${formatDateTime(s.updated_at)}.`}
      />
      <Card>
        <SettingsForm settings={s} />
      </Card>
    </>
  );
}
