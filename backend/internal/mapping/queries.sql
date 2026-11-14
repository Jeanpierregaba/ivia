-- name: SearchPlaces :many
SELECT p.id, p.name, p.category, p.address_label, p.source,
       ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng
FROM places p
WHERE p.is_active AND p.country_code = sqlc.arg(country)
  AND (similarity(p.name, sqlc.arg(q)::text) > 0.25
       OR strpos(lower(p.name), lower(sqlc.arg(q)::text)) > 0
       OR EXISTS (SELECT 1 FROM unnest(p.aliases) a WHERE strpos(lower(a), lower(sqlc.arg(q)::text)) > 0))
ORDER BY similarity(p.name, sqlc.arg(q)::text) DESC, p.usage_count DESC,
         ST_Distance(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography)
LIMIT sqlc.arg(lim);

-- name: NearestPlace :one
-- Lieu Ivia à moins de 50 m : son nom passe avant l'adresse de Nominatim.
SELECT p.name FROM places p
WHERE p.is_active AND p.source <> 'user'
  AND ST_DWithin(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, 50)
ORDER BY ST_Distance(p.location, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography)
LIMIT 1;

-- name: GetPlace :one
SELECT p.id, p.name, p.aliases, p.category, p.address_label, p.source, p.usage_count, p.is_active,
       ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng
FROM places p WHERE p.id = $1;

-- name: TouchPlace :exec
UPDATE places SET usage_count = usage_count + 1, updated_at = now() WHERE id = $1;

-- name: LearnGooglePlace :one
-- Lieu Google choisi par un utilisateur : la base Ivia s'enrichit et les appels diminuent.
INSERT INTO places (name, address_label, location, country_code, source, external_id, usage_count)
VALUES (sqlc.arg(name), sqlc.arg(address_label),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        sqlc.arg(country), 'google', sqlc.arg(external_id), 1)
ON CONFLICT (source, external_id) WHERE external_id IS NOT NULL
DO UPDATE SET usage_count = places.usage_count + 1, name = EXCLUDED.name, address_label = EXCLUDED.address_label, updated_at = now()
RETURNING id;

-- name: AdminListPlaces :many
SELECT p.id, p.name, p.aliases, p.category, p.address_label, p.source, p.usage_count, p.is_active,
       ST_Y(p.location::geometry)::float8 AS lat, ST_X(p.location::geometry)::float8 AS lng
FROM places p
WHERE (sqlc.narg(q)::text IS NULL OR strpos(lower(p.name), lower(sqlc.narg(q)::text)) > 0)
ORDER BY p.usage_count DESC, p.name
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: CreatePlace :one
INSERT INTO places (name, aliases, category, address_label, location, country_code, source, external_id)
VALUES (sqlc.arg(name), sqlc.arg(aliases), sqlc.arg(category), sqlc.arg(address_label),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
        sqlc.arg(country), sqlc.arg(source), sqlc.narg(external_id))
ON CONFLICT (source, external_id) WHERE external_id IS NOT NULL DO UPDATE SET updated_at = now()
RETURNING id;

-- name: UpdatePlace :execrows
UPDATE places SET name = sqlc.arg(name), aliases = sqlc.arg(aliases), category = sqlc.arg(category),
       address_label = sqlc.arg(address_label),
       location = ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
       is_active = sqlc.arg(is_active), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: ListUserPlaces :many
SELECT u.id, u.label, u.type, u.address_label, ST_Y(u.location::geometry)::float8 AS lat, ST_X(u.location::geometry)::float8 AS lng
FROM user_places u WHERE u.user_id = $1
ORDER BY CASE u.type WHEN 'home' THEN 0 WHEN 'work' THEN 1 WHEN 'favorite' THEN 2 ELSE 3 END, u.last_used_at DESC
LIMIT 30;

-- name: CreateUserPlace :one
INSERT INTO user_places (user_id, label, type, location, address_label)
VALUES (sqlc.arg(user_id), sqlc.arg(label), sqlc.arg(type),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, sqlc.arg(address_label))
RETURNING id;

-- name: TrimRecentPlaces :exec
-- Dix dernières destinations au plus.
DELETE FROM user_places u WHERE u.user_id = $1 AND u.type = 'recent' AND u.id NOT IN (
  SELECT r.id FROM user_places r WHERE r.user_id = $1 AND r.type = 'recent' ORDER BY r.last_used_at DESC LIMIT 10);

-- name: DeleteUserPlace :execrows
DELETE FROM user_places WHERE id = $1 AND user_id = $2;

-- name: DeleteUserPlacesOf :exec
DELETE FROM user_places WHERE user_id = $1;

-- name: ListZones :many
SELECT z.id, z.name, z.type, z.rules, z.is_active, ST_AsGeoJSON(z.area::geometry)::text AS geojson
FROM zones z ORDER BY z.type, z.name;

-- name: GetZone :one
SELECT z.id, z.name, z.type, z.rules, z.is_active, ST_AsGeoJSON(z.area::geometry)::text AS geojson
FROM zones z WHERE z.id = $1;

-- name: CreateZone :one
INSERT INTO zones (name, type, area, rules, is_active)
VALUES (sqlc.arg(name), sqlc.arg(type), ST_GeomFromGeoJSON(sqlc.arg(geojson)::text)::geography, sqlc.arg(rules), sqlc.arg(is_active))
RETURNING id;

-- name: UpdateZone :execrows
UPDATE zones SET name = sqlc.arg(name), type = sqlc.arg(type), area = ST_GeomFromGeoJSON(sqlc.arg(geojson)::text)::geography,
       rules = sqlc.arg(rules), is_active = sqlc.arg(is_active), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: DeleteZone :execrows
DELETE FROM zones WHERE id = $1;

-- name: ZonesAt :many
SELECT z.id, z.name, z.type, z.rules FROM zones z
WHERE z.is_active AND ST_Covers(z.area, ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography);

-- name: CountServiceAreas :one
SELECT count(*) FROM zones WHERE is_active AND type = 'service_area';

-- name: InsertTripPoint :exec
INSERT INTO trip_points (trip_id, recorded_at, location, speed, heading)
VALUES (sqlc.arg(trip_id), sqlc.arg(recorded_at),
        ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography, sqlc.narg(speed), sqlc.narg(heading));

-- name: ListTripPoints :many
SELECT t.recorded_at, ST_Y(t.location::geometry)::float8 AS lat, ST_X(t.location::geometry)::float8 AS lng
FROM trip_points t WHERE t.trip_id = $1 ORDER BY t.recorded_at LIMIT 5000;

-- name: PurgeTripPoints :execrows
DELETE FROM trip_points WHERE recorded_at < $1;

-- name: BumpMetric :exec
INSERT INTO geo_metrics (day, metric, value) VALUES (current_date, $1, $2)
ON CONFLICT (day, metric) DO UPDATE SET value = geo_metrics.value + EXCLUDED.value;

-- name: ListMetrics :many
SELECT day, metric, value FROM geo_metrics WHERE day >= $1 ORDER BY day DESC, metric;
