-- name: ListNeighborhoods :many
SELECT id, city, name, is_active,
       (center IS NOT NULL)::boolean AS has_center,
       coalesce(ST_Y(center::geometry), 0)::float8 AS lat,
       coalesce(ST_X(center::geometry), 0)::float8 AS lng
FROM neighborhoods
WHERE (sqlc.arg(include_inactive)::boolean OR is_active)
ORDER BY city, name;

-- name: GetNeighborhood :one
SELECT id, city, name, is_active,
       (center IS NOT NULL)::boolean AS has_center,
       coalesce(ST_Y(center::geometry), 0)::float8 AS lat,
       coalesce(ST_X(center::geometry), 0)::float8 AS lng
FROM neighborhoods
WHERE id = $1;

-- name: CreateNeighborhood :one
INSERT INTO neighborhoods (city, name, center)
VALUES (
  sqlc.arg(city), sqlc.arg(name),
  CASE WHEN sqlc.narg(lat)::float8 IS NULL THEN NULL
       ELSE ST_SetSRID(ST_MakePoint(sqlc.narg(lng)::float8, sqlc.narg(lat)::float8), 4326)::geography END
)
RETURNING id;

-- name: UpdateNeighborhood :one
UPDATE neighborhoods
SET name       = sqlc.arg(name),
    is_active  = sqlc.arg(is_active),
    center     = CASE WHEN sqlc.narg(lat)::float8 IS NULL THEN center
                      ELSE ST_SetSRID(ST_MakePoint(sqlc.narg(lng)::float8, sqlc.narg(lat)::float8), 4326)::geography END,
    updated_at = now()
WHERE id = sqlc.arg(id)
RETURNING id;

-- name: DistanceMeters :one
-- Distance à vol d'oiseau entre deux points, en mètres (sphéroïde WGS 84).
SELECT ST_Distance(
  ST_SetSRID(ST_MakePoint(sqlc.arg(from_lng)::float8, sqlc.arg(from_lat)::float8), 4326)::geography,
  ST_SetSRID(ST_MakePoint(sqlc.arg(to_lng)::float8, sqlc.arg(to_lat)::float8), 4326)::geography
)::float8 AS meters;
