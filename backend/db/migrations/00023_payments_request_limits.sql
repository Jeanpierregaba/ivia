-- Limite des nouvelles demandes de paiement (10 par heure par acheteur et par numéro payeur) :
-- comptée sur la table elle-même, durable (redémarrages, déploiements) et exacte. Ces index
-- gardent le comptage rapide.

-- +goose Up
CREATE INDEX payments_buyer_recent_idx ON payments (buyer_id, created_at);
CREATE INDEX payments_phone_recent_idx ON payments (payer_phone, created_at);

-- +goose Down
DROP INDEX payments_phone_recent_idx;
DROP INDEX payments_buyer_recent_idx;
