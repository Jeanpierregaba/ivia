import "server-only";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import type { components } from "./api-types";

// Appels à l'API Go, exécutés uniquement côté serveur Next.js (ADR 0003) : le jeton de session
// reste dans un cookie httpOnly et n'atteint jamais le JavaScript du navigateur.

export const SESSION_COOKIE = "ivia_admin_session";

export type Schemas = components["schemas"];

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly fields: Record<string, string> = {},
  ) {
    super(message);
  }
}

function baseUrl(): string {
  const url = process.env.API_BASE_URL;
  if (!url) throw new Error("API_BASE_URL non définie (voir .env.example)");
  return url.replace(/\/$/, "");
}

export async function sessionToken(): Promise<string | undefined> {
  return (await cookies()).get(SESSION_COOKIE)?.value;
}

type Options = {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  query?: Record<string, string | number | boolean | undefined | null>;
  // anonymous : appel sans jeton (connexion).
  anonymous?: boolean;
};

/**
 * Appelle l'API et retourne le corps JSON. Une session expirée ou révoquée renvoie vers la
 * connexion ; toute autre erreur devient une ApiError au message français, affichable tel quel.
 */
export async function api<T>(path: string, opts: Options = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (!opts.anonymous) {
    const token = await sessionToken();
    if (!token) redirect("/login");
    headers.Authorization = `Bearer ${token}`;
  }
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";

  const url = new URL(baseUrl() + path);
  for (const [k, v] of Object.entries(opts.query ?? {})) {
    if (v !== undefined && v !== null && v !== "") url.searchParams.set(k, String(v));
  }

  let res: Response;
  try {
    res = await fetch(url, {
      method: opts.method ?? "GET",
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      cache: "no-store",
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new ApiError(0, "network_error", "L'API ne répond pas. Réessayez dans un instant.");
  }

  if (res.status === 401 && !opts.anonymous) redirect("/logout");
  if (res.status === 204) return undefined as T;

  const payload: unknown = await res.json().catch(() => null);
  if (!res.ok) {
    const err = (payload as Schemas["Error"] | null)?.error;
    throw new ApiError(
      res.status,
      err?.code ?? "unknown_error",
      err?.message ?? "Une erreur inattendue est survenue.",
      err?.fields ?? {},
    );
  }
  return payload as T;
}

/** Résultat d'une Server Action, affiché par le formulaire qui l'a déclenchée. */
export type ActionResult =
  { ok: true; message: string } | { ok: false; message: string; fields?: Record<string, string> };

export function failure(err: unknown): ActionResult {
  if (err instanceof ApiError) return { ok: false, message: err.message, fields: err.fields };
  throw err; // redirections Next.js et erreurs inattendues
}

/**
 * Appel brut (fichier CSV) : même jeton et mêmes règles que api(), corps renvoyé tel quel.
 * Réservé aux Route Handlers qui relaient un fichier au navigateur.
 */
export async function apiRaw(path: string, query: Record<string, string>): Promise<Response> {
  const token = await sessionToken();
  if (!token) redirect("/login");
  const url = new URL(baseUrl() + path);
  for (const [k, v] of Object.entries(query)) if (v) url.searchParams.set(k, v);
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
    signal: AbortSignal.timeout(30_000),
  });
  if (res.status === 401) redirect("/logout");
  return res;
}
