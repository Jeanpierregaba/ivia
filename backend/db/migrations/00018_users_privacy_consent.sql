-- Consentement au traitement des données personnelles (loi togolaise n° 2019-014), daté par le
-- serveur à la première acceptation. Il n'est pas retiré ici : on le retire en supprimant son compte.

-- +goose Up
ALTER TABLE users ADD COLUMN privacy_consent_at timestamptz;

-- +goose Down
ALTER TABLE users DROP COLUMN privacy_consent_at;
