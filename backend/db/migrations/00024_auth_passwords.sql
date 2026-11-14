-- Connexion par mot de passe et par Google (ADR 0011, remplace la connexion par code seule de
-- l'ADR 0006). Le code par e-mail ne sert plus qu'à la création du compte, au mot de passe oublié
-- et à la double vérification des admins.

-- +goose Up
-- Usage d'un code : login (ancienne connexion par code, en retrait), signup, reset, mfa.
-- Les codes existants gardent leur sens (login).
ALTER TABLE otp_codes
  ADD COLUMN purpose text NOT NULL DEFAULT 'login'
  CHECK (purpose IN ('login', 'signup', 'reset', 'mfa'));
CREATE INDEX otp_codes_purpose_idx ON otp_codes (channel, recipient, purpose, created_at DESC);

-- Mot de passe : haché (Argon2id, format PHC), jamais en clair. Verrou après trop d'échecs.
CREATE TABLE auth_passwords (
  user_id         uuid PRIMARY KEY REFERENCES users (id),
  password_hash   text NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  locked_until    timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Comptes externes rattachés (Google) : identifiant stable du fournisseur (sub), pas l'e-mail.
CREATE TABLE auth_identities (
  provider   text NOT NULL CHECK (provider IN ('google')),
  subject    text NOT NULL CHECK (length(subject) BETWEEN 1 AND 255),
  user_id    uuid NOT NULL REFERENCES users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (provider, subject)
);
CREATE INDEX auth_identities_user_idx ON auth_identities (user_id);

-- Double vérification (admins) : date de vérification du code et plafond de durée de la session.
ALTER TABLE sessions
  ADD COLUMN mfa_verified_at timestamptz,
  ADD COLUMN expires_cap timestamptz;

-- +goose Down
ALTER TABLE sessions DROP COLUMN expires_cap, DROP COLUMN mfa_verified_at;
DROP TABLE auth_identities;
DROP TABLE auth_passwords;
DROP INDEX otp_codes_purpose_idx;
ALTER TABLE otp_codes DROP COLUMN purpose;
