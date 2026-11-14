import { apiRaw } from "@/lib/api";

// Relaie le CSV de l'API (séparateur ;) au navigateur : le jeton reste côté serveur.
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const date = /^\d{4}-\d{2}-\d{2}$/;
  const from = params.get("from") ?? "";
  const to = params.get("to") ?? "";
  if (!date.test(from) || !date.test(to)) {
    return new Response("Période invalide.", { status: 400 });
  }
  const res = await apiRaw("/v1/admin/deliveries/export", { from, to, format: "csv" });
  if (!res.ok) {
    return new Response("Export impossible pour le moment. Réessayez.", { status: res.status });
  }
  return new Response(res.body, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="livraisons-${from}-${to}.csv"`,
      "Cache-Control": "no-store",
    },
  });
}
