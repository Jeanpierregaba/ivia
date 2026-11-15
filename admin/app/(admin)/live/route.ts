import { apiStream } from "@/lib/api";

export const dynamic = "force-dynamic";

// Relaie au navigateur le flux SSE de l'API (le jeton reste côté serveur) : notifications des
// admins, étapes des courses, positions des livreurs (spec 036).
export async function GET(request: Request) {
  let res: Response;
  try {
    res = await apiStream("/v1/admin/stream", request.signal);
  } catch {
    return new Response("Flux indisponible.", { status: 502 });
  }
  if (!res.ok || !res.body) return new Response(null, { status: res.status || 502 });
  return new Response(res.body, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-store, no-transform",
      "X-Accel-Buffering": "no",
      Connection: "keep-alive",
    },
  });
}
