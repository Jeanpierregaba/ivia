import { MapPin, Plus, Shapes, Store } from "lucide-react";

import { ServerForm } from "@/components/server-form";
import { Card, CardTitle, ErrorState, Field, fieldClass, FilterTabs, PageHeader } from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { saveEntry } from "./actions";

export const metadata = { title: "Référentiels" };

const TABS = [
  { value: "categories", label: "Catégories de produits" },
  { value: "shop-categories", label: "Catégories de boutique" },
  { value: "neighborhoods", label: "Quartiers" },
] as const;

type Tab = (typeof TABS)[number]["value"];
type Props = { searchParams: Promise<{ tab?: string }> };

const small = fieldClass.replace("w-full", "w-24");

export default async function ReferentialsPage({ searchParams }: Props) {
  const raw = (await searchParams).tab;
  const tab: Tab = TABS.some((t) => t.value === raw) ? (raw as Tab) : "categories";

  let categories: Schemas["Category"][] = [];
  let shopCategories: Schemas["AdminShopCategory"][] = [];
  let neighborhoods: Schemas["Neighborhood"][] = [];
  try {
    if (tab === "categories") {
      categories = (await api<{ items: Schemas["Category"][] }>("/v1/admin/categories")).items;
    } else if (tab === "shop-categories") {
      shopCategories = (await api<{ items: Schemas["AdminShopCategory"][] }>("/v1/admin/shop-categories"))
        .items;
    } else {
      neighborhoods = (await api<{ items: Schemas["Neighborhood"][] }>("/v1/admin/neighborhoods")).items;
    }
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const parents = categories.filter((c) => !c.parent_id);

  return (
    <>
      <PageHeader
        overline="Plateforme"
        title="Référentiels de la plateforme"
        highlight="Référentiels"
        description="Listes proposées aux marchands et aux acheteurs. Désactivez une entrée plutôt que de la supprimer : ce qui y est déjà rattaché reste intact."
      />
      <FilterTabs current={tab} tabs={TABS.map((t) => ({ ...t, href: `/referentials?tab=${t.value}` }))} />

      {tab === "categories" && (
        <Section icon={<Shapes size={18} aria-hidden="true" />} title="Catégories de produits">
          {categories.map((c) => (
            <Row key={c.id} kind="categories" id={c.id} active={c.is_active}>
              <NameField value={c.name} />
              <ParentField parents={parents.filter((p) => p.id !== c.id)} value={c.parent_id} />
              <PositionField value={c.position} />
            </Row>
          ))}
          <AddRow kind="categories">
            <NameField />
            <ParentField parents={parents} value={null} />
            <PositionField value={(categories.length + 1) * 10} />
          </AddRow>
        </Section>
      )}

      {tab === "shop-categories" && (
        <Section icon={<Store size={18} aria-hidden="true" />} title="Catégories de boutique">
          {shopCategories.map((c) => (
            <Row key={c.id} kind="shop-categories" id={c.id} active={c.is_active}>
              <NameField value={c.name} max={60} />
              <PositionField value={c.position} />
            </Row>
          ))}
          <AddRow kind="shop-categories">
            <NameField max={60} />
            <PositionField value={(shopCategories.length + 1) * 10} />
          </AddRow>
        </Section>
      )}

      {tab === "neighborhoods" && (
        <Section icon={<MapPin size={18} aria-hidden="true" />} title="Quartiers">
          {neighborhoods.map((n) => (
            <Row key={n.id} kind="neighborhoods" id={n.id} active={n.is_active}>
              <NameField value={n.name} />
              <CityField value={n.city} />
            </Row>
          ))}
          <AddRow kind="neighborhoods">
            <NameField />
            <CityField value="Lomé" />
          </AddRow>
        </Section>
      )}
    </>
  );
}

function Section({
  icon,
  title,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <Card>
      <CardTitle icon={icon}>{title}</CardTitle>
      <div className="divide-y divide-border">{children}</div>
    </Card>
  );
}

/** Ligne modifiable : champs, case « Active », bouton « Enregistrer », message de l'API. */
function Row({
  kind,
  id,
  active,
  children,
}: {
  kind: string;
  id: string;
  active: boolean;
  children: React.ReactNode;
}) {
  return (
    <ServerForm action={saveEntry} submitLabel="Enregistrer" variant="outline" inline className="py-3">
      <input type="hidden" name="kind" value={kind} />
      <input type="hidden" name="id" value={id} />
      {children}
      <ActiveField checked={active} />
    </ServerForm>
  );
}

function AddRow({ kind, children }: { kind: string; children: React.ReactNode }) {
  return (
    <div className="pt-5">
      <p className="mb-2 flex items-center gap-1.5 text-[12px] font-semibold uppercase tracking-[0.08em] text-secondary">
        <Plus size={14} aria-hidden="true" /> Ajouter
      </p>
      <ServerForm action={saveEntry} submitLabel="Ajouter" variant="imperial" inline>
        <input type="hidden" name="kind" value={kind} />
        {children}
        <ActiveField checked />
      </ServerForm>
    </div>
  );
}

function NameField({ value, max = 100 }: { value?: string; max?: number }) {
  return (
    <div className="min-w-56 flex-1">
      <Field label="Nom">
        <input name="name" defaultValue={value} required maxLength={max} className={fieldClass} />
      </Field>
    </div>
  );
}

function PositionField({ value }: { value: number }) {
  return (
    <Field label="Ordre">
      <input name="position" type="number" min={0} step={1} defaultValue={value} className={small} />
    </Field>
  );
}

function CityField({ value }: { value: string }) {
  return (
    <div className="w-40">
      <Field label="Ville">
        <input name="city" defaultValue={value} required maxLength={100} className={fieldClass} />
      </Field>
    </div>
  );
}

function ParentField({ parents, value }: { parents: Schemas["Category"][]; value: string | null }) {
  return (
    <div className="w-52">
      <Field label="Catégorie parente">
        <select name="parent_id" defaultValue={value ?? ""} className={fieldClass}>
          <option value="">Aucune (principale)</option>
          {parents.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
      </Field>
    </div>
  );
}

function ActiveField({ checked }: { checked: boolean }) {
  return (
    <label className="flex h-11 items-center gap-2 px-1 text-[13px] font-semibold text-text-secondary">
      <input type="checkbox" name="is_active" defaultChecked={checked} className="size-4 accent-[#004DA8]" />
      Active
    </label>
  );
}
