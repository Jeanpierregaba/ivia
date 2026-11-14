-- name: CreateShop :one
INSERT INTO shops (owner_id, name, description, phone, address_text, neighborhood_id, location, logo_key, category_id)
VALUES (
  sqlc.arg(owner_id), sqlc.arg(name), sqlc.arg(description), sqlc.arg(phone), sqlc.arg(address_text),
  sqlc.narg(neighborhood_id),
  ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
  sqlc.narg(logo_key), sqlc.narg(category_id)
)
RETURNING id;

-- name: GetShop :one
SELECT s.id, s.owner_id, s.name, s.description, s.phone, s.address_text, s.neighborhood_id, s.logo_key,
       s.status, s.status_reason, s.accepting_orders, s.managed_by_platform, s.reviewed_at, s.reviewed_by, s.created_at, s.updated_at,
       ST_Y(s.location::geometry)::float8 AS lat,
       ST_X(s.location::geometry)::float8 AS lng,
       s.category_id, coalesce(c.name, '')::text AS category_name
FROM shops s
LEFT JOIN shop_categories c ON c.id = s.category_id
WHERE s.id = $1;

-- name: ListShopsByOwner :many
SELECT s.id, s.owner_id, s.name, s.description, s.phone, s.address_text, s.neighborhood_id, s.logo_key,
       s.status, s.status_reason, s.accepting_orders, s.managed_by_platform, s.reviewed_at, s.reviewed_by, s.created_at, s.updated_at,
       ST_Y(s.location::geometry)::float8 AS lat,
       ST_X(s.location::geometry)::float8 AS lng,
       s.category_id, coalesce(c.name, '')::text AS category_name
FROM shops s
LEFT JOIN shop_categories c ON c.id = s.category_id
WHERE s.owner_id = $1
ORDER BY s.created_at;

-- name: CountShopsByOwner :one
SELECT count(*) FROM shops WHERE owner_id = $1;

-- name: ListShopsByStatus :many
SELECT s.id, s.owner_id, s.name, s.description, s.phone, s.address_text, s.neighborhood_id, s.logo_key,
       s.status, s.status_reason, s.accepting_orders, s.managed_by_platform, s.reviewed_at, s.reviewed_by, s.created_at, s.updated_at,
       ST_Y(s.location::geometry)::float8 AS lat,
       ST_X(s.location::geometry)::float8 AS lng,
       s.category_id, coalesce(c.name, '')::text AS category_name
FROM shops s
LEFT JOIN shop_categories c ON c.id = s.category_id
WHERE (sqlc.narg(status)::text IS NULL OR s.status = sqlc.narg(status)::text)
  AND (sqlc.narg(q)::text IS NULL OR immutable_unaccent(lower(s.name)) LIKE '%' || immutable_unaccent(lower(sqlc.narg(q)::text)) || '%')
ORDER BY s.created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: UpdateShop :exec
UPDATE shops
SET name             = sqlc.arg(name),
    description      = sqlc.arg(description),
    phone            = sqlc.arg(phone),
    address_text     = sqlc.arg(address_text),
    neighborhood_id  = sqlc.narg(neighborhood_id),
    location         = ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
    logo_key         = sqlc.narg(logo_key),
    category_id      = sqlc.narg(category_id),
    accepting_orders = sqlc.arg(accepting_orders),
    updated_at       = now()
WHERE id = sqlc.arg(id);

-- name: SetShopStatus :execrows
-- Transition conditionnelle : échoue si le statut a changé entre-temps.
UPDATE shops
SET status = sqlc.arg(new_status), status_reason = sqlc.arg(reason),
    reviewed_at = now(), reviewed_by = sqlc.narg(reviewed_by), updated_at = now()
WHERE id = sqlc.arg(id) AND status = ANY(sqlc.arg(from_statuses)::text[]);

-- name: SuspendShopsOfOwner :exec
UPDATE shops
SET status = 'suspended', status_reason = sqlc.arg(reason), accepting_orders = false, updated_at = now()
WHERE owner_id = sqlc.arg(owner_id) AND status <> 'suspended';

-- name: ListShopIDsByOwner :many
SELECT id FROM shops WHERE owner_id = $1;

-- name: ListAllShopCategories :many
SELECT * FROM shop_categories ORDER BY position, name;

-- name: GetShopCategory :one
SELECT * FROM shop_categories WHERE id = $1;

-- name: CreateShopCategory :one
INSERT INTO shop_categories (name, position) VALUES ($1, $2) RETURNING *;

-- name: UpdateShopCategory :one
UPDATE shop_categories SET name = $2, position = $3, is_active = $4 WHERE id = $1 RETURNING *;

-- name: ListActiveShopCategories :many
SELECT id, name FROM shop_categories WHERE is_active ORDER BY position, name;

-- name: ShopCategoryIsActive :one
SELECT EXISTS (SELECT 1 FROM shop_categories WHERE id = $1 AND is_active);

-- name: InsertMerchantDocument :one
INSERT INTO merchant_documents (owner_id, kind, object_key) VALUES ($1, $2, $3) RETURNING *;

-- name: ListMerchantDocuments :many
SELECT * FROM merchant_documents WHERE owner_id = $1 ORDER BY created_at;

-- name: CountMerchantDocuments :one
SELECT count(*) FROM merchant_documents WHERE owner_id = $1;

-- name: DeleteMerchantDocumentsOf :exec
DELETE FROM merchant_documents WHERE owner_id = $1;

-- name: MerchantDocumentKeysIn :many
-- Clés rattachées parmi celles données (purge des fichiers jamais rattachés).
SELECT object_key FROM merchant_documents WHERE object_key = ANY(sqlc.arg(keys)::text[]);

-- name: PendingShopsOverview :one
-- Boutiques à valider et date de la plus ancienne (tableau de bord).
SELECT count(*)::bigint AS n, coalesce(min(created_at), now())::timestamptz AS oldest
FROM shops WHERE status = 'pending_review';

-- name: SetManagedByPlatform :execrows
UPDATE shops SET managed_by_platform = sqlc.arg(managed), updated_at = now() WHERE id = sqlc.arg(id);

-- name: ListManagedShopIDs :many
SELECT id FROM shops WHERE managed_by_platform ORDER BY created_at;
