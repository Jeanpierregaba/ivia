import { api, ApiError } from "@/lib/api";

// Relaie la carte de la flotte au navigateur (le jeton reste côté serveur) : positions récentes, ou
// trajet d'un livreur avec ?trail=<id>.
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const trail = params.get("trail") ?? "";
  const hours = Math.min(168, Math.max(1, Number(params.get("hours") ?? 24) || 24));
  try {
    const body = /^[0-9a-f-]{36}$/i.test(trail)
      ? await api(`/v1/admin/fleet/${trail}/trail`, { query: { hours } })
      : await api("/v1/admin/fleet", { query: { hours } });
    return Response.json(body, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    if (err instanceof ApiError) return Response.json({ message: err.message }, { status: err.status });
    throw err;
  }
}
