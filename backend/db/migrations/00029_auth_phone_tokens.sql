-- Connexion par numéro de téléphone (code WhatsApp, SMS en secours), jetons d'accès courts et
-- jetons de rafraîchissement, appareils connus, double vérification des admins par application
-- d'authentification (ADR 0012, spec 001 v2). Migration additive : aucune donnée supprimée.

-- +goose Up

-- Identifiant « phone » : un même code peut partir par WhatsApp puis par SMS (secours) ; le canal
-- réellement utilisé est noté dans sent_via. Nouveaux usages : connexion par numéro et changement
-- de numéro.
ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_channel_check;
ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_channel_check
  CHECK (channel IN ('email', 'phone', 'whatsapp', 'sms'));
ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_purpose_check;
ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_purpose_check
  CHECK (purpose IN ('login', 'signup', 'reset', 'mfa', 'phone_login', 'phone_change'));
ALTER TABLE otp_codes
  ADD COLUMN sent_via text CHECK (sent_via IN ('email', 'whatsapp', 'sms'));
CREATE INDEX otp_codes_phone_created_idx ON otp_codes (created_at) WHERE channel = 'phone';

-- Numéro vérifié par un code : c'est alors l'identifiant de connexion du compte.
ALTER TABLE users ADD COLUMN phone_verified_at timestamptz;

-- Numéro verrouillé après trop de codes faux (15 min).
CREATE TABLE auth_recipient_locks (
  channel      text NOT NULL,
  recipient    text NOT NULL,
  locked_until timestamptz NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel, recipient)
);

-- Inscription en attente : le numéro est prouvé, le compte n'existe pas encore (nom à saisir).
-- Seul le SHA-256 du jeton est gardé ; expire 15 minutes après la vérification du code.
CREATE TABLE auth_pending_signups (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash  bytea NOT NULL UNIQUE,
  phone       text NOT NULL CHECK (phone ~ '^\+228[0-9]{8}$'),
  expires_at  timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auth_pending_signups_expires_idx ON auth_pending_signups (expires_at);

-- Appareils connus d'un compte : l'identifiant d'installation envoyé par l'app n'est gardé que
-- haché. Un appareil inconnu déclenche une alerte « nouvelle connexion ».
CREATE TABLE auth_devices (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users (id),
  device_hash  bytea NOT NULL,
  name         text NOT NULL DEFAULT '' CHECK (length(name) <= 80),
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_hash)
);

-- Jetons : le jeton de session devient un jeton d'accès court (access_expires_at) quand la
-- session a un jeton de rafraîchissement, changé à chaque usage (l'ancien est gardé pour détecter
-- sa réutilisation, signe de vol). Les sessions sans rafraîchissement gardent leur fonctionnement.
ALTER TABLE sessions
  ADD COLUMN refresh_hash          bytea UNIQUE,
  ADD COLUMN previous_refresh_hash bytea,
  ADD COLUMN refreshed_at          timestamptz,
  ADD COLUMN access_expires_at     timestamptz,
  ADD COLUMN device_id             uuid REFERENCES auth_devices (id) ON DELETE SET NULL,
  ADD COLUMN app                   text;
CREATE INDEX sessions_previous_refresh_idx ON sessions (previous_refresh_hash) WHERE previous_refresh_hash IS NOT NULL;

-- Double vérification par application d'authentification (TOTP, RFC 6238). Le secret est chiffré
-- (AES-GCM, clé dérivée de AUTH_SECRET) ; last_step empêche de rejouer un code déjà utilisé.
CREATE TABLE auth_totp (
  user_id      uuid PRIMARY KEY REFERENCES users (id),
  secret_enc   bytea NOT NULL,
  confirmed_at timestamptz,
  last_step    bigint NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Codes de secours (téléphone perdu) : usage unique, hachés.
CREATE TABLE auth_recovery_codes (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   uuid NOT NULL REFERENCES users (id),
  code_hash bytea NOT NULL,
  used_at   timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auth_recovery_codes_user_idx ON auth_recovery_codes (user_id);

-- +goose Down
DROP TABLE auth_recovery_codes;
DROP TABLE auth_totp;
DROP INDEX sessions_previous_refresh_idx;
ALTER TABLE sessions
  DROP COLUMN app, DROP COLUMN device_id, DROP COLUMN access_expires_at, DROP COLUMN refreshed_at,
  DROP COLUMN previous_refresh_hash, DROP COLUMN refresh_hash;
DROP TABLE auth_devices;
DROP TABLE auth_pending_signups;
DROP TABLE auth_recipient_locks;
ALTER TABLE users DROP COLUMN phone_verified_at;
DROP INDEX otp_codes_phone_created_idx;
ALTER TABLE otp_codes DROP COLUMN sent_via;
ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_purpose_check;
ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_purpose_check
  CHECK (purpose IN ('login', 'signup', 'reset', 'mfa'));
ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_channel_check;
ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_channel_check
  CHECK (channel IN ('email', 'whatsapp', 'sms'));
