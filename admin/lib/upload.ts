import "server-only";

import { api, ApiError } from "./api";

// Envoi d'une image par le serveur Next.js : le navigateur poste le fichier à une Server Action,
// qui demande une URL signée à l'API puis y dépose le fichier. Le jeton ne quitte pas le serveur.

const TYPES = ["image/jpeg", "image/png", "image/webp"];
const MAX_BYTES = 5 << 20;

export type UploadPurpose = "product_image" | "promo_visual";

/** Dépose une image et retourne sa clé ; null si aucun fichier n'a été choisi. */
export async function uploadImage(
  file: FormDataEntryValue | null,
  purpose: UploadPurpose,
): Promise<string | null> {
  if (!(file instanceof File) || file.size === 0) return null;
  if (!TYPES.includes(file.type))
    throw new ApiError(400, "validation_failed", "Image JPEG, PNG ou WebP attendue.");
  if (file.size > MAX_BYTES) throw new ApiError(400, "validation_failed", "L'image doit faire au plus 5 Mo.");

  const up = await api<{
    object_key: string;
    upload: { url: string; method: string; headers?: Record<string, string> };
  }>("/v1/uploads", { method: "POST", body: { purpose, content_type: file.type, size_bytes: file.size } });
  const res = await fetch(up.upload.url, {
    method: up.upload.method || "PUT",
    headers: { "Content-Type": file.type, ...(up.upload.headers ?? {}) },
    body: Buffer.from(await file.arrayBuffer()),
    signal: AbortSignal.timeout(60_000),
  });
  if (!res.ok) throw new ApiError(502, "upload_failed", "L'envoi de l'image a échoué. Réessayez.");
  return up.object_key;
}
