-- name: CreateShop :one
INSERT INTO shops (owner_id, name, description, phone, address_text, neighborhood_id, location, logo_key)
VALUES (
  sqlc.arg(owner_id), sqlc.arg(name), sqlc.arg(description), sqlc.arg(phone), sqlc.arg(address_text),
  sqlc.narg(neighborhood_id),
  ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
  sqlc.narg(logo_key)
)
RETURNING id;

-- name: GetShop :one
SELECT s.id, s.owner_id, s.name, s.description, s.phone, s.address_text, s.neighborhood_id, s.logo_key,
       s.status, s.status_reason, s.accepting_orders, s.reviewed_at, s.reviewed_by, s.created_at, s.updated_at,
       ST_Y(s.location::geometry)::float8 AS lat,
       ST_X(s.location::geometry)::float8 AS lng
FROM shops s
WHERE s.id = $1;

-- name: ListShopsByOwner :many
SELECT s.id, s.owner_id, s.name, s.description, s.phone, s.address_text, s.neighborhood_id, s.logo_key,
       s.status, s.status_reason, s.accepting_orders, s.reviewed_at, s.reviewed_by, s.created_at, s.updated_at,
       ST_Y(s.location::geometry)::float8 AS lat,
       ST_X(s.location::geometry)::float8 AS lng
FROM shops s
WHERE s.owner_id = $1
ORDER BY s.created_at;

-- name: CountShopsByOwner :one
SELECT count(*) FROM shops WHERE owner_id = $1;

-- name: ListShopsByStatus :many
SELECT s.id, s.owner_id, s.name, s.description, s.phone, s.address_text, s.neighborhood_id, s.logo_key,
       s.status, s.status_reason, s.accepting_orders, s.reviewed_at, s.reviewed_by, s.created_at, s.updated_at,
       ST_Y(s.location::geometry)::float8 AS lat,
       ST_X(s.location::geometry)::float8 AS lng
FROM shops s
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
