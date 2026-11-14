import { Download, Search } from "lucide-react";

import {
  buttonClass,
  Card,
  EmptyState,
  ErrorState,
  Field,
  fieldClass,
  PageHeader,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatXOF, frDate, lomeDate, VEHICLE } from "@/lib/format";

export const metadata = { title: "Livraisons par livreur" };

type Props = { searchParams: Promise<{ from?: string; to?: string }> };

/** Période proposée : du 1er du mois en cours à aujourd'hui (heure de Lomé). */
function defaultPeriod(): { from: string; to: string } {
  const today = lomeDate(new Date());
  return { from: today.slice(0, 8) + "01", to: today };
}

export default async function DeliveriesPage({ searchParams }: Props) {
  const sp = await searchParams;
  const period = defaultPeriod();
  const from = sp.from ?? period.from;
  const to = sp.to ?? period.to;

  let rows: Schemas["ExportRow"][];
  try {
    rows = (
      await api<{ items: Schemas["ExportRow"][] }>("/v1/admin/deliveries/export", { query: { from, to } })
    ).items;
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const total = rows.reduce(
    (t, r) => ({ delivered: t.delivered + r.delivered, fees: t.fees + r.delivered_fees_xof }),
    { delivered: 0, fees: 0 },
  );
  const csv = `/deliveries/export?${new URLSearchParams({ from, to })}`;

  return (
    <>
      <PageHeader
        overline="Flotte"
        title="Livraisons par livreur"
        highlight="Livraisons"
        description="Livraisons réussies, échouées et retirées sur la période (dates de Lomé), avec les frais de livraison encaissés : la base de la paie des livreurs."
        actions={
          rows.length > 0 && (
            <a href={csv} className={buttonClass("imperial")}>
              <Download size={18} aria-hidden="true" /> Télécharger le CSV
            </a>
          )
        }
      />

      <Card className="mb-6">
        <form action="/deliveries" className="grid grid-cols-1 lg:grid-cols-[1fr_1fr_auto] items-end gap-3">
          <Field label="Du">
            <input type="date" name="from" defaultValue={from} required className={fieldClass} />
          </Field>
          <Field label="Au">
            <input type="date" name="to" defaultValue={to} required className={fieldClass} />
          </Field>
          <button className={buttonClass("primary")}>
            <Search size={17} aria-hidden="true" /> Afficher
          </button>
        </form>
      </Card>

      {rows.length === 0 ? (
        <EmptyState
          title="Aucune livraison"
          message={`Aucune livraison entre le ${frDate(from)} et le ${frDate(to)}.`}
        />
      ) : (
        <Table head={["Livreur", "Véhicule", "Réussies", "Échouées", "Retirées", "Frais encaissés"]}>
          {rows.map((r) => (
            <tr key={r.driver_id}>
              <Td className="font-semibold">{r.first_name || "—"}</Td>
              <Td>{VEHICLE[r.vehicle_type] ?? r.vehicle_type}</Td>
              <Td className="font-semibold">{r.delivered}</Td>
              <Td>{r.failed}</Td>
              <Td>{r.withdrawn}</Td>
              <Td className="font-semibold">{formatXOF(r.delivered_fees_xof)}</Td>
            </tr>
          ))}
          <tr className="bg-background">
            <Td className="font-bold">Total</Td>
            <Td>{rows.length} livreur(s)</Td>
            <Td className="font-bold">{total.delivered}</Td>
            <Td>—</Td>
            <Td>—</Td>
            <Td className="font-bold text-primary-strong">{formatXOF(total.fees)}</Td>
          </tr>
        </Table>
      )}
    </>
  );
}
