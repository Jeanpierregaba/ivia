-- name: GetUser :one
SELECT * FROM users WHERE id = $1;

-- name: GetUserByEmail :one
SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL;

-- name: CreateUser :one
-- Sans effet (aucune ligne) si l'e-mail existe déjà : inscription simultanée.
INSERT INTO users (email) VALUES ($1) ON CONFLICT (email) DO NOTHING RETURNING *;

-- name: GetUserByPhone :one
SELECT * FROM users WHERE phone = $1 AND deleted_at IS NULL;

-- name: CreateUserWithPhone :one
-- Compte créé après la vérification du numéro (connexion par numéro) : numéro vérifié, nom et
-- consentement datés. Sans effet (aucune ligne) si le numéro est déjà pris.
INSERT INTO users (phone, phone_verified_at, first_name, last_name, privacy_consent_at)
VALUES (sqlc.arg(phone), now(), sqlc.arg(first_name), sqlc.arg(last_name), now())
ON CONFLICT (phone) DO NOTHING
RETURNING *;

-- name: MarkPhoneVerified :exec
UPDATE users SET phone_verified_at = now(), updated_at = now()
WHERE id = $1 AND phone_verified_at IS NULL;

-- name: SetVerifiedPhone :one
-- Changement de numéro confirmé par un code.
UPDATE users SET phone = sqlc.arg(phone), phone_verified_at = now(), updated_at = now()
WHERE id = sqlc.arg(id) AND deleted_at IS NULL
RETURNING *;

-- name: UpdateProfile :one
UPDATE users
SET first_name = sqlc.arg(first_name),
    last_name  = sqlc.arg(last_name),
    phone      = sqlc.narg(phone),
    -- Daté à la première acceptation, jamais retiré ni redaté.
    privacy_consent_at = coalesce(
      privacy_consent_at,
      CASE WHEN sqlc.arg(accept_privacy_policy)::boolean THEN now() END
    ),
    updated_at = now()
WHERE id = sqlc.arg(id) AND deleted_at IS NULL
RETURNING *;

-- name: AnonymizeUser :exec
UPDATE users
SET email = NULL, phone = NULL, phone_verified_at = NULL, avatar_key = NULL, first_name = '', last_name = '',
    deleted_at = now(), updated_at = now()
WHERE id = $1 AND deleted_at IS NULL;

-- name: ListRoles :many
SELECT role FROM user_roles WHERE user_id = $1 ORDER BY role;

-- name: GrantRole :exec
INSERT INTO user_roles (user_id, role, granted_by)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, role) DO NOTHING;

-- name: RevokeRole :execrows
DELETE FROM user_roles WHERE user_id = $1 AND role = $2;

-- name: RevokeAllRoles :exec
DELETE FROM user_roles WHERE user_id = $1;

-- name: CountRoleHolders :one
SELECT count(*) FROM user_roles r JOIN users u ON u.id = r.user_id
WHERE r.role = $1 AND u.deleted_at IS NULL;

-- name: SearchUsers :many
SELECT u.*, coalesce(array_agg(r.role ORDER BY r.role) FILTER (WHERE r.role IS NOT NULL), '{}')::text[] AS roles
FROM users u
LEFT JOIN user_roles r ON r.user_id = u.id
WHERE u.deleted_at IS NULL
  AND (sqlc.narg(q)::text IS NULL
       OR u.email ILIKE '%' || sqlc.narg(q)::text || '%'
       OR u.phone LIKE '%' || sqlc.narg(q)::text || '%'
       OR immutable_unaccent(lower(u.first_name || ' ' || u.last_name)) LIKE '%' || immutable_unaccent(lower(sqlc.narg(q)::text)) || '%')
  AND (sqlc.narg(role)::text IS NULL
       OR EXISTS (SELECT 1 FROM user_roles x WHERE x.user_id = u.id AND x.role = sqlc.narg(role)::text))
GROUP BY u.id
ORDER BY u.created_at DESC
LIMIT sqlc.arg(lim) OFFSET sqlc.arg(off);

-- name: ListAddresses :many
SELECT a.id, a.label, a.address_text, a.neighborhood_id, a.instructions, a.created_at, a.updated_at,
       ST_Y(a.location::geometry)::float8 AS lat,
       ST_X(a.location::geometry)::float8 AS lng
FROM addresses a
WHERE a.user_id = $1
ORDER BY a.created_at;

-- name: GetAddress :one
SELECT a.id, a.label, a.address_text, a.neighborhood_id, a.instructions, a.created_at, a.updated_at,
       ST_Y(a.location::geometry)::float8 AS lat,
       ST_X(a.location::geometry)::float8 AS lng
FROM addresses a
WHERE a.id = sqlc.arg(id) AND a.user_id = sqlc.arg(user_id);

-- name: CountAddresses :one
SELECT count(*) FROM addresses WHERE user_id = $1;

-- name: CreateAddress :one
INSERT INTO addresses (user_id, label, address_text, neighborhood_id, location, instructions)
VALUES (
  sqlc.arg(user_id), sqlc.arg(label), sqlc.arg(address_text), sqlc.narg(neighborhood_id),
  ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
  sqlc.arg(instructions)
)
RETURNING id;

-- name: UpdateAddress :execrows
UPDATE addresses
SET label           = sqlc.arg(label),
    address_text    = sqlc.arg(address_text),
    neighborhood_id = sqlc.narg(neighborhood_id),
    location        = ST_SetSRID(ST_MakePoint(sqlc.arg(lng)::float8, sqlc.arg(lat)::float8), 4326)::geography,
    instructions    = sqlc.arg(instructions),
    updated_at      = now()
WHERE id = sqlc.arg(id) AND user_id = sqlc.arg(user_id);

-- name: DeleteAddress :execrows
DELETE FROM addresses WHERE id = sqlc.arg(id) AND user_id = sqlc.arg(user_id);

-- name: DeleteAllAddresses :exec
DELETE FROM addresses WHERE user_id = $1;

-- name: UpsertDeviceToken :exec
-- Un jeton push appartient au dernier compte connecté sur l'appareil.
INSERT INTO device_tokens (user_id, token, platform, app)
VALUES ($1, $2, $3, $4)
ON CONFLICT (token) DO UPDATE
SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, app = EXCLUDED.app, last_seen_at = now();

-- name: DeleteDeviceToken :exec
DELETE FROM device_tokens WHERE user_id = $1 AND token = $2;

-- name: DeleteDeviceTokenByValue :exec
DELETE FROM device_tokens WHERE token = $1;

-- name: DeleteAllDeviceTokens :exec
DELETE FROM device_tokens WHERE user_id = $1;

-- name: ListDeviceTokens :many
SELECT token FROM device_tokens WHERE user_id = $1 AND app = $2;

-- name: ListUserIDsByRole :many
SELECT r.user_id FROM user_roles r JOIN users u ON u.id = r.user_id
WHERE r.role = $1 AND u.deleted_at IS NULL;

-- name: SetAvatar :one
UPDATE users SET avatar_key = sqlc.narg(avatar_key), updated_at = now()
WHERE id = sqlc.arg(id) AND deleted_at IS NULL
RETURNING *;
