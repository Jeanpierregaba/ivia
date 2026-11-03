-- name: CountRecentOTP :one
-- Nombre de codes envoyés à un destinataire depuis une date : pour un usage (limite par minute)
-- ou tous usages confondus si purpose est NULL (limite par jour).
SELECT count(*) FROM otp_codes
WHERE channel = sqlc.arg(channel) AND recipient = sqlc.arg(recipient) AND created_at > sqlc.arg(since)
  AND (sqlc.narg(purpose)::text IS NULL OR purpose = sqlc.narg(purpose)::text);

-- name: LockRecipient :exec
-- Sérialise les demandes de code d'un même destinataire (limites exactes même en concurrence).
SELECT pg_advisory_xact_lock(hashtextextended(sqlc.arg(channel)::text || ':' || sqlc.arg(recipient)::text, 0));

-- name: InvalidateOTPs :exec
-- Un nouveau code annule les précédents du même usage : un seul code valable à la fois.
UPDATE otp_codes SET consumed_at = now()
WHERE channel = $1 AND recipient = $2 AND purpose = $3 AND consumed_at IS NULL;

-- name: CreateOTP :one
INSERT INTO otp_codes (channel, recipient, purpose, code_hash, expires_at)
VALUES ($1, $2, $3, $4, $5)
RETURNING id;

-- name: LatestActiveOTP :one
SELECT * FROM otp_codes
WHERE channel = $1 AND recipient = $2 AND purpose = $3 AND consumed_at IS NULL
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
SELECT id, user_id, expires_at, last_used_at, mfa_verified_at FROM sessions
WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now();

-- name: TouchSession :exec
-- Expiration glissante, jamais au-delà du plafond d'une session admin (expires_cap).
UPDATE sessions SET last_used_at = now(),
  expires_at = least(sqlc.arg(expires_at)::timestamptz, coalesce(expires_cap, sqlc.arg(expires_at)::timestamptz))
WHERE id = sqlc.arg(id);

-- name: MarkSessionMFA :one
-- Code de double vérification accepté : la session est plafonnée (8 h pour le back-office).
UPDATE sessions SET mfa_verified_at = now(), expires_cap = sqlc.arg(cap)::timestamptz,
  expires_at = least(expires_at, sqlc.arg(cap)::timestamptz)
WHERE id = sqlc.arg(id) AND revoked_at IS NULL
RETURNING expires_at;

-- name: GetSession :one
SELECT id, user_id, expires_at, mfa_verified_at FROM sessions
WHERE id = $1 AND revoked_at IS NULL AND expires_at > now();

-- name: RevokeOtherSessions :exec
-- Mot de passe changé ou réinitialisé : tous les autres appareils sont déconnectés.
UPDATE sessions SET revoked_at = now()
WHERE user_id = sqlc.arg(user_id) AND id <> sqlc.arg(keep) AND revoked_at IS NULL;

-- name: GetPassword :one
SELECT * FROM auth_passwords WHERE user_id = $1;

-- name: SetPassword :exec
INSERT INTO auth_passwords (user_id, password_hash) VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE
SET password_hash = EXCLUDED.password_hash, failed_attempts = 0, locked_until = NULL, updated_at = now();

-- name: RecordLoginFailure :one
-- Échec compté ; au-delà du seuil, compte verrouillé pour la durée donnée (compteur remis à zéro).
UPDATE auth_passwords
SET failed_attempts = CASE WHEN failed_attempts + 1 >= sqlc.arg(max_attempts)::int THEN 0 ELSE failed_attempts + 1 END,
    locked_until = CASE WHEN failed_attempts + 1 >= sqlc.arg(max_attempts)::int
                        THEN now() + make_interval(secs => sqlc.arg(lock_seconds)::int) ELSE locked_until END
WHERE user_id = sqlc.arg(user_id)
RETURNING locked_until;

-- name: ResetLoginFailures :exec
UPDATE auth_passwords SET failed_attempts = 0, locked_until = NULL
WHERE user_id = $1 AND (failed_attempts > 0 OR locked_until IS NOT NULL);

-- name: DeletePassword :exec
DELETE FROM auth_passwords WHERE user_id = $1;

-- name: GetIdentity :one
SELECT * FROM auth_identities WHERE provider = $1 AND subject = $2;

-- name: CreateIdentity :exec
INSERT INTO auth_identities (provider, subject, user_id) VALUES ($1, $2, $3)
ON CONFLICT (provider, subject) DO NOTHING;

-- name: DeleteIdentitiesOf :exec
DELETE FROM auth_identities WHERE user_id = $1;

-- name: RevokeSession :exec
UPDATE sessions SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL;

-- name: RevokeUserSessions :exec
UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL;

-- name: PurgeSessions :execrows
DELETE FROM sessions
WHERE expires_at < now() - interval '7 days' OR revoked_at < now() - interval '7 days';
