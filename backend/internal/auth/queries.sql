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

-- name: SetOTPSentVia :exec
-- Canal réellement utilisé (WhatsApp, ou SMS en secours).
UPDATE otp_codes SET sent_via = $2 WHERE id = $1;

-- name: CountRecentPhoneOTPs :one
-- Plafond global des codes envoyés par WhatsApp ou SMS (protection contre la fraude aux SMS).
SELECT count(*) FROM otp_codes WHERE channel = 'phone' AND created_at > sqlc.arg(since);

-- name: GetRecipientLock :one
SELECT locked_until FROM auth_recipient_locks
WHERE channel = $1 AND recipient = $2 AND locked_until > now();

-- name: LockRecipientUntil :exec
INSERT INTO auth_recipient_locks (channel, recipient, locked_until) VALUES ($1, $2, $3)
ON CONFLICT (channel, recipient) DO UPDATE SET locked_until = EXCLUDED.locked_until, created_at = now();

-- name: InvalidateAllOTPs :exec
-- Numéro verrouillé : tous ses codes en cours sont annulés.
UPDATE otp_codes SET consumed_at = now()
WHERE channel = $1 AND recipient = $2 AND consumed_at IS NULL;

-- name: CreatePendingSignup :exec
INSERT INTO auth_pending_signups (token_hash, phone, expires_at) VALUES ($1, $2, $3);

-- name: ConsumePendingSignup :one
-- Usage unique : seule la première requête obtient le numéro.
UPDATE auth_pending_signups SET consumed_at = now()
WHERE token_hash = $1 AND consumed_at IS NULL AND expires_at > now()
RETURNING phone;

-- name: UpsertDevice :one
-- Appareil retrouvé ou ajouté ; inserted vaut vrai pour un nouvel appareil.
INSERT INTO auth_devices (user_id, device_hash, name) VALUES ($1, $2, $3)
ON CONFLICT (user_id, device_hash) DO UPDATE
SET last_seen_at = now(), name = CASE WHEN EXCLUDED.name = '' THEN auth_devices.name ELSE EXCLUDED.name END
RETURNING id, (xmax = 0)::boolean AS inserted;

-- name: CountDevices :one
SELECT count(*) FROM auth_devices WHERE user_id = $1;

-- name: DeleteDevicesOf :exec
DELETE FROM auth_devices WHERE user_id = $1;

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
SELECT id, user_id, expires_at, last_used_at, mfa_verified_at, access_expires_at FROM sessions
WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now();

-- name: CreateRefreshableSession :one
-- Session avec jeton d'accès court et jeton de rafraîchissement (apps mobiles).
INSERT INTO sessions (user_id, token_hash, refresh_hash, user_agent, expires_at, access_expires_at, device_id, app)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id, expires_at;

-- name: GetSessionByRefresh :one
SELECT id, user_id, expires_at, expires_cap FROM sessions
WHERE refresh_hash = $1 AND revoked_at IS NULL AND expires_at > now();

-- name: GetSessionByPreviousRefresh :one
SELECT id, refreshed_at FROM sessions
WHERE previous_refresh_hash = $1 AND revoked_at IS NULL;

-- name: RotateSession :execrows
-- Nouveau couple de jetons ; échoue (0 ligne) si un autre rafraîchissement est passé avant.
UPDATE sessions
SET token_hash = sqlc.arg(token_hash), refresh_hash = sqlc.arg(refresh_hash),
    previous_refresh_hash = sqlc.arg(old_refresh_hash), refreshed_at = now(), last_used_at = now(),
    access_expires_at = sqlc.arg(access_expires_at),
    expires_at = least(sqlc.arg(expires_at)::timestamptz, coalesce(expires_cap, sqlc.arg(expires_at)::timestamptz))
WHERE id = sqlc.arg(id) AND refresh_hash = sqlc.arg(old_refresh_hash) AND revoked_at IS NULL;

-- name: ListUserSessions :many
-- Appareils connectés d'un utilisateur (écran « Appareils connectés »).
SELECT s.id, s.user_agent, s.app, s.created_at, s.last_used_at, s.expires_at, s.mfa_verified_at,
       coalesce(d.name, '')::text AS device_name
FROM sessions s LEFT JOIN auth_devices d ON d.id = s.device_id
WHERE s.user_id = $1 AND s.revoked_at IS NULL AND s.expires_at > now()
ORDER BY s.last_used_at DESC;

-- name: RevokeUserSession :execrows
UPDATE sessions SET revoked_at = now() WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL;

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

-- name: PurgePendingSignups :execrows
DELETE FROM auth_pending_signups WHERE expires_at < now() - interval '1 day';

-- name: PurgeRecipientLocks :execrows
DELETE FROM auth_recipient_locks WHERE locked_until < now();

-- name: GetTOTP :one
SELECT * FROM auth_totp WHERE user_id = $1;

-- name: UpsertTOTP :exec
-- Nouveau secret à confirmer : remplace un secret non confirmé.
INSERT INTO auth_totp (user_id, secret_enc) VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE SET secret_enc = EXCLUDED.secret_enc, confirmed_at = NULL, last_step = 0, created_at = now();

-- name: ConfirmTOTP :exec
UPDATE auth_totp SET confirmed_at = now() WHERE user_id = $1;

-- name: AdvanceTOTPStep :execrows
-- Anti-rejeu : un code (pas de 30 s) ne sert qu'une fois.
UPDATE auth_totp SET last_step = sqlc.arg(step) WHERE user_id = sqlc.arg(user_id) AND last_step < sqlc.arg(step);

-- name: DeleteTOTP :exec
DELETE FROM auth_totp WHERE user_id = $1;

-- name: CreateRecoveryCode :exec
INSERT INTO auth_recovery_codes (user_id, code_hash) VALUES ($1, $2);

-- name: DeleteRecoveryCodes :exec
DELETE FROM auth_recovery_codes WHERE user_id = $1;

-- name: UseRecoveryCode :execrows
UPDATE auth_recovery_codes SET used_at = now()
WHERE user_id = $1 AND code_hash = $2 AND used_at IS NULL;

-- name: CountRecoveryCodesLeft :one
SELECT count(*) FROM auth_recovery_codes WHERE user_id = $1 AND used_at IS NULL;

-- name: PurgeSessions :execrows
DELETE FROM sessions
WHERE expires_at < now() - interval '7 days' OR revoked_at < now() - interval '7 days';
