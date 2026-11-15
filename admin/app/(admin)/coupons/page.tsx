import { Gift, TicketPercent } from "lucide-react";

import { ActionForm } from "@/components/action-form";
import { ServerForm } from "@/components/server-form";
import {
  Card,
  CardTitle,
  EmptyState,
  ErrorState,
  Field,
  fieldClass,
  FilterTabs,
  PageHeader,
  Pagination,
  StatusBadge,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatXOF, frDate, type Tone } from "@/lib/format";
import { codeAction, createCode, updateWelcome } from "./actions";
import { ProductScope } from "./product-scope";

export const metadata = { title: "Codes promo" };

const LIMIT = 30;
const STATE: Record<string, { label: string; tone: Tone }> = {
  active: { label: "Actif", tone: "success" },
  scheduled: { label: "Programmé", tone: "info" },
  suspended: { label: "Suspendu", tone: "warning" },
  ended: { label: "Terminé", tone: "muted" },
};

type Code = Schemas["PromoCode"];
type Props = { searchParams: Promise<{ tab?: string; offset?: string }> };

function valueOf(c: Code) {
  if (c.kind === "percent")
    return `-${c.value} %${c.max_discount_xof ? ` (max ${formatXOF(c.max_discount_xof)})` : ""}`;
  return `-${formatXOF(c.value)}`;
}

export default async function CouponsPage({ searchParams }: Props) {
  const sp = await searchParams;
  const tab = sp.tab === "welcome" ? "welcome" : "";
  const offset = Number(sp.offset ?? 0) || 0;

  let page: { items: Code[]; next_offset?: number | null };
  let settings: Schemas["CouponSettings"];
  let shops: Schemas["Shop"][];
  try {
    [page, settings, shops] = await Promise.all([
      api<{ items: Code[]; next_offset?: number | null }>("/v1/admin/promo-codes", {
        query: { limit: LIMIT, offset, welcome: tab === "welcome" ? "true" : "false" },
      }),
      api<Schemas["CouponSettings"]>("/v1/admin/coupon-settings"),
      api<{ items: Schemas["Shop"][] }>("/v1/admin/shops", {
        query: { status: "published", limit: 100 },
      }).then((r) => r.items),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const items = tab === "welcome" ? page.items.filter((c) => c.welcome) : page.items;
  const given = items.reduce((n, c) => n + (c.discount_given_xof ?? 0), 0);

  return (
    <>
      <PageHeader
        overline="Marketing"
        title="Codes promo et coupons"
        highlight="coupons"
        description="Codes des boutiques (à leurs frais), codes de la boutique IVI et coupon de bienvenue offert par ivia."
      />

      <div className="mb-6 grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Card>
          <CardTitle icon={<Gift size={18} aria-hidden="true" />}>Coupon de bienvenue</CardTitle>
          <p className="mb-4 text-text-secondary">
            Offert par ivia à chaque nouveau compte, pour sa première commande. Le marchand reçoit autant que
            sans coupon.
          </p>
          <ServerForm action={updateWelcome} submitLabel="Enregistrer">
            <label className="flex items-center gap-3 font-semibold">
              <input
                type="checkbox"
                name="welcome_enabled"
                defaultChecked={settings.welcome_enabled}
                className="size-5 accent-primary"
              />
              Activé
            </label>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <Field label="Montant offert (F)">
                <input
                  name="welcome_amount_xof"
                  inputMode="numeric"
                  defaultValue={settings.welcome_amount_xof}
                  className={fieldClass}
                />
              </Field>
              <Field label="Achat minimum (F)">
                <input
                  name="welcome_min_order_xof"
                  inputMode="numeric"
                  defaultValue={settings.welcome_min_order_xof}
                  className={fieldClass}
                />
              </Field>
              <Field label="Valable (jours)">
                <input
                  name="welcome_valid_days"
                  inputMode="numeric"
                  defaultValue={settings.welcome_valid_days}
                  className={fieldClass}
                />
              </Field>
            </div>
          </ServerForm>
        </Card>

        <Card>
          <CardTitle icon={<TicketPercent size={18} aria-hidden="true" />}>
            Créer un code (boutique IVI)
          </CardTitle>
          <ServerForm action={createCode} submitLabel="Créer le code" variant="imperial">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <ProductScope shops={shops.map((s) => ({ id: s.id, name: s.name }))} />
              <Field label="Code" hint="Vide : code généré">
                <input name="code" maxLength={24} className={`${fieldClass} uppercase`} />
              </Field>
              <Field label="Type">
                <select name="kind" className={fieldClass}>
                  <option value="percent">Pourcentage</option>
                  <option value="fixed">Montant fixe</option>
                </select>
              </Field>
              <Field label="Réduction (% ou F)">
                <input name="value" inputMode="numeric" required className={fieldClass} />
              </Field>
              <Field label="Plafond (F, pourcentage)">
                <input name="max_discount_xof" inputMode="numeric" className={fieldClass} />
              </Field>
              <Field label="Achat minimum (F)">
                <input name="min_order_xof" inputMode="numeric" className={fieldClass} />
              </Field>
              <Field label="Utilisations au total">
                <input name="max_uses" inputMode="numeric" className={fieldClass} />
              </Field>
              <Field label="Durée (jours)" hint="Vide : sans fin">
                <input name="days" inputMode="numeric" defaultValue={30} className={fieldClass} />
              </Field>
            </div>
            <label className="flex items-center gap-3">
              <input type="checkbox" name="private" className="size-5 accent-primary" />
              Code privé (absent de « Mes coupons »)
            </label>
          </ServerForm>
        </Card>
      </div>

      <FilterTabs
        current={tab}
        tabs={[
          { value: "", label: "Codes des boutiques", href: "/coupons" },
          { value: "welcome", label: "Coupons de bienvenue", href: "/coupons?tab=welcome" },
        ]}
      />
      <p className="mb-3 text-text-secondary">
        Réductions accordées sur cette page : <strong>{formatXOF(given)}</strong>
      </p>

      {items.length === 0 ? (
        <EmptyState
          title="Aucun code"
          message="Les codes créés par les boutiques et par ivia s'afficheront ici."
        />
      ) : (
        <Table head={["Code", "Boutique", "Réduction", "Utilisations", "Offert", "Fin", "État", ""]}>
          {items.map((c) => {
            const st = STATE[c.state] ?? { label: "Actif", tone: "success" as Tone };
            return (
              <tr key={c.id}>
                <Td className="font-bold tracking-wide">{c.code}</Td>
                <Td>
                  {c.shop_name}
                  <span className="block text-[12px] text-text-muted">
                    {c.funded_by === "ivia" ? "Payé par ivia" : "Payé par la boutique"}
                  </span>
                </Td>
                <Td>
                  {valueOf(c)}
                  <span className="block text-[12px] text-text-muted">
                    {c.scope === "products"
                      ? c.products.length === 1
                        ? `Sur ${c.products[0]?.name ?? ""}`
                        : `Sur ${c.products.length} produits`
                      : "Toute la boutique"}
                  </span>
                </Td>
                <Td className="tabular-nums">
                  {c.used_count ?? 0}
                  {c.max_uses ? ` / ${c.max_uses}` : ""}
                </Td>
                <Td className="tabular-nums">{formatXOF(c.discount_given_xof ?? 0)}</Td>
                <Td>{c.ends_at ? frDate(c.ends_at) : "—"}</Td>
                <Td>
                  <StatusBadge label={st.label} tone={st.tone} />
                  {c.suspension_reason && (
                    <span className="mt-1 block text-[12px] text-text-muted">{c.suspension_reason}</span>
                  )}
                </Td>
                <Td>
                  {c.status === "active" && (
                    <ActionForm
                      action={codeAction}
                      label="Suspendre"
                      variant="outline"
                      hidden={{ id: c.id, action: "suspend" }}
                      reason={{ label: "Motif de la suspension", required: true }}
                    />
                  )}
                  {c.status === "suspended" && (
                    <ActionForm
                      action={codeAction}
                      label="Reprendre"
                      variant="outline"
                      hidden={{ id: c.id, action: "resume" }}
                    />
                  )}
                </Td>
              </tr>
            );
          })}
        </Table>
      )}
      <Pagination
        basePath="/coupons"
        params={{ tab: tab || undefined }}
        offset={offset}
        nextOffset={page.next_offset}
        limit={LIMIT}
      />
    </>
  );
}
