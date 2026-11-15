import { cookies } from "next/headers";
import { NextResponse, type NextRequest } from "next/server";

import { SESSION_COOKIE } from "@/lib/api";

// Déconnexion : session révoquée côté API, cookie effacé. Aussi utilisée quand l'API refuse la
// session (expirée, révoquée, rôle admin retiré).
async function logout(req: NextRequest) {
  const store = await cookies();
  const token = store.get(SESSION_COOKIE)?.value;
  if (token && process.env.API_BASE_URL) {
    await fetch(`${process.env.API_BASE_URL}/v1/auth/logout`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(5_000),
    }).catch(() => undefined);
  }
  store.delete(SESSION_COOKIE);
  return NextResponse.redirect(new URL("/login", req.url), { status: 303 });
}

export const GET = logout;
export const POST = logout;
