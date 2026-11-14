import { api, ApiError } from "@/lib/api";

type Product = { id: string; name: string; price_xof: number; is_active: boolean };

// Relaie au navigateur les produits en vente d'une boutique (choix des produits d'un code promo,
// spec 041) ; le jeton reste côté serveur.
export async function GET(request: Request) {
  const shop = new URL(request.url).searchParams.get("shop") ?? "";
  if (!/^[0-9a-f-]{36}$/i.test(shop)) return Response.json({ items: [] });
  try {
    const page = await api<{ items: Product[] }>("/v1/admin/products", {
      query: { shop_id: shop, limit: 100 },
    });
    const items = page.items
      .filter((p) => p.is_active)
      .map((p) => ({ id: p.id, name: p.name, price_xof: p.price_xof }));
    return Response.json({ items }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    if (err instanceof ApiError) return Response.json({ message: err.message }, { status: err.status });
    throw err;
  }
}
