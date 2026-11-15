-- name: CreateSpace :one
INSERT INTO business_spaces (owner_id, sector, name, details) VALUES ($1, $2, $3, $4) RETURNING *;

-- name: GetSpace :one
SELECT * FROM business_spaces WHERE id = $1;

-- name: LockSpace :one
SELECT * FROM business_spaces WHERE id = $1 FOR UPDATE;

-- name: ListSpacesOfOwner :many
SELECT * FROM business_spaces WHERE owner_id = $1 ORDER BY created_at;

-- name: CountSpacesOfOwner :one
SELECT count(*) FROM business_spaces WHERE owner_id = $1;

-- name: AdminListSpaces :many
SELECT * FROM business_spaces
WHERE (sqlc.narg(status)::text IS NULL OR status = sqlc.narg(status)::text)
  AND (sqlc.narg(sector)::text IS NULL OR sector = sqlc.narg(sector)::text)
ORDER BY coalesce(submitted_at, created_at) DESC, id
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: UpdateSpaceDetails :exec
UPDATE business_spaces SET name = $2, details = $3, updated_at = now() WHERE id = $1;

-- name: SetSpacePayout :exec
UPDATE business_spaces SET payout_operator = $2, payout_phone = $3, payout_holder = $4, updated_at = now() WHERE id = $1;

-- name: SetSpaceShop :exec
UPDATE business_spaces SET shop_id = $2, updated_at = now() WHERE id = $1;

-- name: MarkSpaceSubmitted :exec
UPDATE business_spaces SET status = 'pending_review', status_reason = '', submitted_at = now(), updated_at = now() WHERE id = $1;

-- name: SetSpaceReview :exec
UPDATE business_spaces SET status = $2, status_reason = $3, reviewed_by = $4, reviewed_at = now(), updated_at = now() WHERE id = $1;

-- name: SyncSpaceFromShop :exec
UPDATE business_spaces SET status = $2, status_reason = $3, reviewed_at = now(), updated_at = now() WHERE shop_id = $1;

-- name: SuspendSpacesOfOwner :exec
-- Suppression du compte : plus de compte de versement ni d'activité.
UPDATE business_spaces SET status = 'suspended', status_reason = $2, payout_operator = NULL, payout_phone = NULL,
       payout_holder = '', updated_at = now()
WHERE owner_id = $1;

-- name: ListDocuments :many
SELECT * FROM business_documents WHERE space_id = $1 ORDER BY created_at;

-- name: GetDocumentKey :one
SELECT object_key FROM business_documents WHERE space_id = $1 AND kind = $2;

-- name: UpsertDocument :exec
INSERT INTO business_documents (space_id, kind, object_key) VALUES ($1, $2, $3)
ON CONFLICT (space_id, kind) DO UPDATE SET object_key = EXCLUDED.object_key, created_at = now();

-- name: DeleteDocumentsOfOwner :exec
DELETE FROM business_documents d USING business_spaces s WHERE d.space_id = s.id AND s.owner_id = $1;

-- name: DocumentKeysIn :many
SELECT object_key FROM business_documents WHERE object_key = ANY(sqlc.arg(keys)::text[]);

-- name: ListItems :many
SELECT * FROM business_items WHERE space_id = $1 ORDER BY created_at DESC;

-- name: CountItems :one
SELECT count(*) FROM business_items WHERE space_id = $1;

-- name: CreateItem :one
INSERT INTO business_items (space_id, title, description, price_xof, status, attributes, photo_keys)
VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *;

-- name: GetItemOfOwner :one
SELECT i.*, s.status AS space_status FROM business_items i
JOIN business_spaces s ON s.id = i.space_id
WHERE i.id = $1 AND s.owner_id = $2;

-- name: UpdateItem :one
UPDATE business_items SET title = $2, description = $3, price_xof = $4, status = $5, attributes = $6, photo_keys = $7,
       updated_at = now()
WHERE id = $1 RETURNING *;

-- name: DeleteItem :execrows
DELETE FROM business_items i USING business_spaces s
WHERE i.id = $1 AND i.space_id = s.id AND s.owner_id = $2;

-- name: PinExists :one
SELECT EXISTS (SELECT 1 FROM business_pins WHERE user_id = $1);

-- name: GetPinHash :one
SELECT pin_hash FROM business_pins WHERE user_id = $1;

-- name: UpsertPin :exec
INSERT INTO business_pins (user_id, pin_hash) VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE SET pin_hash = EXCLUDED.pin_hash, failed_attempts = 0, locked_until = NULL, updated_at = now();

-- name: ReservePinAttempt :execrows
-- Compte l'essai avant de vérifier le code : des essais simultanés ne dépassent pas la limite.
-- Sans ligne modifiée : compte verrouillé.
UPDATE business_pins SET
  failed_attempts = CASE WHEN locked_until IS NOT NULL THEN 1 ELSE failed_attempts + 1 END,
  locked_until = CASE WHEN locked_until IS NULL AND failed_attempts + 1 >= sqlc.arg(max_attempts)::int
                      THEN now() + make_interval(mins => sqlc.arg(lock_minutes)::int) END,
  updated_at = now()
WHERE user_id = sqlc.arg(user_id) AND (locked_until IS NULL OR locked_until <= now());

-- name: ResetPinAttempts :exec
UPDATE business_pins SET failed_attempts = 0, locked_until = NULL, updated_at = now() WHERE user_id = $1;

-- name: DeletePin :exec
DELETE FROM business_pins WHERE user_id = $1;

-- name: OpenSession :exec
INSERT INTO business_sessions (session_id, space_id) VALUES ($1, $2)
ON CONFLICT (session_id) DO UPDATE SET space_id = EXCLUDED.space_id, opened_at = now();

-- name: OpenedSpace :one
SELECT space_id FROM business_sessions WHERE session_id = $1;

-- name: CloseSession :exec
DELETE FROM business_sessions WHERE session_id = $1;
