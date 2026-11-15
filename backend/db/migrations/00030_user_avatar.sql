-- Photo de profil (avatar) des comptes, dans le stockage public. Migration additive.

-- +goose Up
ALTER TABLE users ADD COLUMN avatar_key text CHECK (length(avatar_key) <= 300);

-- +goose Down
ALTER TABLE users DROP COLUMN avatar_key;
