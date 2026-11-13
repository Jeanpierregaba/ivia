import { ShieldCheck, UserPlus } from "lucide-react";
import Link from "next/link";

import { ActionForm } from "@/components/action-form";
import { ServerForm } from "@/components/server-form";
import {
  Avatar,
  Card,
  CardTitle,
  ErrorState,
  Field,
  fieldClass,
  PageHeader,
  Table,
  Td,
} from "@/components/ui";
import { api, ApiError, type Schemas } from "@/lib/api";
import { formatDateTime } from "@/lib/format";
import { createAdmin, removeAdmin, setRole } from "./actions";

export const metadata = { title: "Comptes admin" };

type Data = { items: Schemas["AdminAccount"][]; roles: Schemas["AdminRole"][] };

export default async function AdminsPage() {
  let data: Data;
  let meId: string;
  try {
    [data, meId] = await Promise.all([
      api<Data>("/v1/admin/admins"),
      api<Schemas["User"]>("/v1/me").then((u) => u.id),
    ]);
  } catch (err) {
    if (err instanceof ApiError) return <ErrorState message={err.message} />;
    throw err;
  }
  const roles = data.roles ?? [];

  return (
    <>
      <PageHeader
        overline="Système"
        title="Comptes admin et rôles"
        highlight="rôles"
        description="Chaque admin a un rôle précis : il ne voit que les sections de son domaine. Le super admin voit tout et suit les actions de chacun."
      />

      <div className="mb-6 grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
        <Card>
          <CardTitle icon={<UserPlus size={18} aria-hidden="true" />}>Nouveau compte admin</CardTitle>
          <ServerForm action={createAdmin} submitLabel="Créer le compte" variant="imperial">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Field label="Prénom">
                <input name="first_name" required maxLength={60} className={fieldClass} />
              </Field>
              <Field label="Nom">
                <input name="last_name" required maxLength={60} className={fieldClass} />
              </Field>
            </div>
            <Field
              label="E-mail professionnel"
              hint="Une adresse jamais utilisée sur ivia (pas celle d'un client, d'un marchand ou d'un livreur)."
            >
              <input name="email" type="email" required className={fieldClass} />
            </Field>
            <Field label="Rôle">
              <select name="role" required defaultValue="operations" className={fieldClass}>
                {roles.map((r) => (
                  <option key={r.code} value={r.code}>
                    {r.label}
                  </option>
                ))}
              </select>
            </Field>
          </ServerForm>
          <p className="mt-3 text-[13px] text-text-secondary">
            Le nouvel admin choisit son mot de passe avec « Mot de passe oublié » sur la page de connexion,
            puis confirme chaque connexion par un code.
          </p>
        </Card>

        <Card>
          <CardTitle icon={<ShieldCheck size={18} aria-hidden="true" />}>Les rôles</CardTitle>
          <ul className="space-y-2.5">
            {roles.map((r) => (
              <li key={r.code} className="rounded-[12px] bg-background px-4 py-2.5">
                <p className="font-bold">{r.label}</p>
                <p className="text-[13px] text-text-secondary">{r.description}</p>
              </li>
            ))}
          </ul>
        </Card>
      </div>

      <Table head={["Admin", "Rôle", "Depuis", "Changer le rôle", ""]}>
        {data.items.map((a) => {
          const name = [a.first_name, a.last_name].filter(Boolean).join(" ") || a.email;
          const self = a.id === meId;
          return (
            <tr key={a.id}>
              <Td>
                <div className="flex items-center gap-3">
                  <Avatar name={name} tone={a.role === "super_admin" ? "imperial" : "berkeley"} size={36} />
                  <div>
                    <p className="font-semibold">{name}</p>
                    <p className="text-[13px] text-text-muted">{a.email}</p>
                  </div>
                </div>
              </Td>
              <Td>
                <span
                  className={
                    "rounded-full px-2.5 py-0.5 text-[12px] font-bold " +
                    (a.role === "super_admin"
                      ? "bg-primary-soft text-primary-strong"
                      : "bg-secondary-soft text-tertiary")
                  }
                >
                  {a.role_label}
                </span>
              </Td>
              <Td className="whitespace-nowrap text-text-secondary">{formatDateTime(a.created_at)}</Td>
              <Td>
                {self ? (
                  <span className="text-[13px] text-text-muted">Votre compte</span>
                ) : (
                  <ServerForm action={setRole} submitLabel="Changer" variant="outline" inline>
                    <input type="hidden" name="id" value={a.id} />
                    <select name="role" defaultValue={a.role} className={`${fieldClass} w-44`}>
                      {roles.map((r) => (
                        <option key={r.code} value={r.code}>
                          {r.label}
                        </option>
                      ))}
                    </select>
                  </ServerForm>
                )}
              </Td>
              <Td>
                <div className="flex flex-wrap items-center gap-2">
                  <Link
                    href={`/audit?admin_id=${a.id}`}
                    className="text-[13px] font-semibold text-secondary hover:underline"
                  >
                    Ses actions
                  </Link>
                  {!self && (
                    <ActionForm
                      action={removeAdmin}
                      label="Retirer l'accès"
                      variant="ghost"
                      hidden={{ id: a.id }}
                      confirm={{
                        title: `Retirer l'accès de ${name} ?`,
                        body: "Son accès au back-office est coupé dès sa prochaine page. L'action est journalisée.",
                      }}
                    />
                  )}
                </div>
              </Td>
            </tr>
          );
        })}
      </Table>
    </>
  );
}
