-- Boutiques gérées par ivia (boutique officielle IVI) : leurs commandes sont reçues et traitées au
-- back-office, qui joue le rôle du marchand.

-- +goose Up
ALTER TABLE shops ADD COLUMN managed_by_platform boolean NOT NULL DEFAULT false;
CREATE INDEX shops_managed_by_platform_idx ON shops (id) WHERE managed_by_platform;

-- +goose Down
DROP INDEX shops_managed_by_platform_idx;
ALTER TABLE shops DROP COLUMN managed_by_platform;
