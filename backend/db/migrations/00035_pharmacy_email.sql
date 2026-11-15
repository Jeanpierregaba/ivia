-- E-mail de la pharmacie, renseigné sur sa fiche : il reçoit l'avis de validation. Migration additive.

-- +goose Up
ALTER TABLE pharmacies ADD COLUMN email text NOT NULL DEFAULT '' CHECK (length(email) <= 254);

-- +goose Down
ALTER TABLE pharmacies DROP COLUMN email;
