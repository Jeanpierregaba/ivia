-- name: CountRecentOTP :one
-- Nombre de codes envoyés à un destinataire depuis une date (limite par minute et par jour).
SELECT count(*) FROM otp_codes
WHERE channel = $1 AND recipient = $2 AND created_at > sqlc.arg(since);

-- name: LockRecipient :exec
-- Sérialise les demandes de code d'un même destinataire (limites exactes même en concurrence).
SELECT pg_advisory_xact_lock(hashtextextended(sqlc.arg(channel)::text || ':' || sqlc.arg(recipient)::text, 0));

-- name: InvalidateOTPs :exec
-- Un nouveau code annule les précédents : un seul code valable à la fois.
UPDATE otp_codes SET consumed_at = now()
WHERE channel = $1 AND recipient = $2 AND consumed_at IS NULL;

-- name: CreateOTP :one
INSERT INTO otp_codes (channel, recipient, code_hash, expires_at)
VALUES ($1, $2, $3, $4)
RETURNING id;

-- name: LatestActiveOTP :one
SELECT * FROM otp_codes
WHERE channel = $1 AND recipient = $2 AND consumed_at IS NULL
ORDER BY created_at DESC
LIMIT 1;

-- name: IncrementOTPAttempts :one
-- Compte l'essai avant de comparer le code : deux essais simultanés ne dépassent jamais la limite.
UPDATE otp_codes SET attempts = attempts + 1
WHERE id = $1 AND consumed_at IS NULL AND attempts < sqlc.arg(max_attempts)
RETURNING attempts;

-- name: ConsumeOTP :execrows
-- Usage unique : seule la première requête qui consomme le code réussit.
UPDATE otp_codes SET consumed_at = now() WHERE id = $1 AND consumed_at IS NULL;

-- name: DeleteOTPsFor :exec
DELETE FROM otp_codes WHERE recipient = $1;

-- name: PurgeOTPs :execrows
-- Les codes ne servent plus après 24 h (limite quotidienne comprise).
DELETE FROM otp_codes WHERE created_at < now() - interval '2 days';

-- name: CreateSession :one
INSERT INTO sessions (user_id, token_hash, user_agent, expires_at)
VALUES ($1, $2, $3, $4)
RETURNING id, expires_at;

-- name: GetSessionByHash :one
SELECT id, user_id, expires_at, last_used_at FROM sessions
WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now();

-- name: TouchSession :exec
UPDATE sessions SET last_used_at = now(), expires_at = sqlc.arg(expires_at) WHERE id = sqlc.arg(id);

-- name: RevokeSession :exec
UPDATE sessions SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL;

-- name: RevokeUserSessions :exec
UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL;

-- name: PurgeSessions :execrows
DELETE FROM sessions
WHERE expires_at < now() - interval '7 days' OR revoked_at < now() - interval '7 days';
