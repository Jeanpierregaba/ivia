-- name: ListProperties :many
-- Annonces actives, les plus proches d'abord (sans position : les plus récentes).
SELECT p.id, p.title, p.kind, p.property_type, p.price_xof, p.bedrooms, p.surface_m2, p.neighborhood,
       p.address_text, ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng,
       p.description, p.photo_keys, p.contact_name, p.contact_phone, p.created_at,
       CASE WHEN sqlc.narg(lat)::float8 IS NULL THEN 0
            ELSE ST_Distance(p.location, ST_SetSRID(ST_MakePoint(sqlc.narg(lng)::float8, sqlc.narg(lat)::float8), 4326)::geography)
       END::float8 AS distance_m
FROM properties p
WHERE p.is_active AND (sqlc.narg(kind)::text IS NULL OR p.kind = sqlc.narg(kind)::text)
ORDER BY distance_m, p.created_at DESC
LIMIT sqlc.arg(lim);

-- name: GetProperty :one
SELECT p.id, p.title, p.kind, p.property_type, p.price_xof, p.bedrooms, p.surface_m2, p.neighborhood,
       p.address_text, ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng,
       p.description, p.photo_keys, p.contact_name, p.contact_phone, p.created_at
FROM properties p WHERE p.id = $1 AND p.is_active;

-- name: UpsertProperty :one
-- Annonce de démonstration (local) : créée ou remise à jour par son titre et son quartier.
INSERT INTO properties (title, kind, property_type, price_xof, bedrooms, surface_m2, neighborhood, address_text,
                        location, description, photo_keys, contact_name, contact_phone)
VALUES (sqlc.arg(title), sqlc.arg(kind), sqlc.arg(property_type), sqlc.arg(price_xof), sqlc.arg(bedrooms),
        sqlc.arg(surface_m2), sqlc.arg(neighborhood), sqlc.arg(address_text),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        sqlc.arg(description), sqlc.arg(photo_keys), sqlc.arg(contact_name), sqlc.arg(contact_phone))
ON CONFLICT (title, neighborhood) DO UPDATE SET is_active = true, updated_at = now()
RETURNING id;

-- name: CountPropertyPhotos :one
SELECT cardinality(photo_keys) FROM properties WHERE title = $1 AND neighborhood = $2;

-- name: AdminListProperties :many
-- Back-office : toutes les annonces, retirées comprises, les plus récentes d'abord.
SELECT p.id, p.title, p.kind, p.property_type, p.price_xof, p.bedrooms, p.surface_m2, p.neighborhood,
       p.address_text, ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng,
       p.description, p.photo_keys, p.contact_name, p.contact_phone, p.is_active, p.created_at, p.updated_at
FROM properties p
WHERE (sqlc.narg(search)::text IS NULL
       OR strpos(lower(p.title), lower(sqlc.narg(search)::text)) > 0
       OR strpos(lower(p.neighborhood), lower(sqlc.narg(search)::text)) > 0)
  AND (sqlc.narg(active)::boolean IS NULL OR p.is_active = sqlc.narg(active)::boolean)
ORDER BY p.created_at DESC, p.id
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: AdminGetProperty :one
SELECT p.id, p.title, p.kind, p.property_type, p.price_xof, p.bedrooms, p.surface_m2, p.neighborhood,
       p.address_text, ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng,
       p.description, p.photo_keys, p.contact_name, p.contact_phone, p.is_active, p.created_at, p.updated_at
FROM properties p WHERE p.id = $1;

-- name: LockProperty :one
SELECT p.id, p.title, p.kind, p.property_type, p.price_xof, p.bedrooms, p.surface_m2, p.neighborhood,
       p.address_text, ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng,
       p.description, p.photo_keys, p.contact_name, p.contact_phone, p.is_active, p.created_at, p.updated_at
FROM properties p WHERE p.id = $1 FOR UPDATE;

-- name: InsertProperty :one
INSERT INTO properties (title, kind, property_type, price_xof, bedrooms, surface_m2, neighborhood, address_text,
                        location, description, photo_keys, contact_name, contact_phone, is_active)
VALUES (sqlc.arg(title), sqlc.arg(kind), sqlc.arg(property_type), sqlc.arg(price_xof), sqlc.arg(bedrooms),
        sqlc.arg(surface_m2), sqlc.arg(neighborhood), sqlc.arg(address_text),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        sqlc.arg(description), sqlc.arg(photo_keys), sqlc.arg(contact_name), sqlc.arg(contact_phone), sqlc.arg(is_active))
RETURNING id;

-- name: UpdateProperty :exec
UPDATE properties SET title = sqlc.arg(title), kind = sqlc.arg(kind), property_type = sqlc.arg(property_type),
       price_xof = sqlc.arg(price_xof), bedrooms = sqlc.arg(bedrooms), surface_m2 = sqlc.arg(surface_m2),
       neighborhood = sqlc.arg(neighborhood), address_text = sqlc.arg(address_text),
       location = ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
       description = sqlc.arg(description), photo_keys = sqlc.arg(photo_keys), contact_name = sqlc.arg(contact_name),
       contact_phone = sqlc.arg(contact_phone), is_active = sqlc.arg(is_active), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: SetPropertyActive :exec
UPDATE properties SET is_active = $2, updated_at = now() WHERE id = $1;
