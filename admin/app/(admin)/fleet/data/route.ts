import { api, ApiError } from "@/lib/api";

type Point = { lat: number; lng: number };
type Driver = {
  id: string;
  lat: number;
  lng: number;
  vehicle_type: string;
  target?: Point | null;
  route?: Point[];
};

/** Décode un tracé polyline6 (OSRM). */
function decode(encoded: string): Point[] {
  const out: Point[] = [];
  let i = 0;
  let lat = 0;
  let lng = 0;
  const next = () => {
    let result = 0;
    let shift = 0;
    let b = 0;
    do {
      b = encoded.charCodeAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return result & 1 ? -((result >> 1) + 1) : result >> 1;
  };
  while (i < encoded.length) {
    lat += next();
    lng += next();
    out.push({ lat: lat / 1e6, lng: lng / 1e6 });
  }
  return out;
}

// Relaie la carte de la flotte au navigateur (le jeton reste côté serveur) : positions récentes et
// itinéraire de chaque livreur en course vers la destination de son étape, ou trajet d'un livreur
// avec ?trail=<id>.
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const trail = params.get("trail") ?? "";
  const hours = Math.min(168, Math.max(1, Number(params.get("hours") ?? 24) || 24));
  try {
    if (/^[0-9a-f-]{36}$/i.test(trail)) {
      const body = await api(`/v1/admin/fleet/${trail}/trail`, { query: { hours } });
      return Response.json(body, { headers: { "Cache-Control": "no-store" } });
    }
    const body = await api<{ items: Driver[]; generated_at: string }>("/v1/admin/fleet", {
      query: { hours },
    });
    await Promise.all(
      body.items.map(async (d) => {
        if (!d.target) return;
        try {
          const r = await api<{ polyline: string }>("/v1/geo/route", {
            method: "POST",
            body: {
              origin: { lat: d.lat, lng: d.lng },
              destination: d.target,
              profile: d.vehicle_type === "car" ? "car" : "moto",
            },
          });
          d.route = r.polyline ? decode(r.polyline) : [{ lat: d.lat, lng: d.lng }, d.target];
        } catch {
          d.route = [{ lat: d.lat, lng: d.lng }, d.target];
        }
      }),
    );
    return Response.json(body, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    if (err instanceof ApiError) return Response.json({ message: err.message }, { status: err.status });
    throw err;
  }
}
