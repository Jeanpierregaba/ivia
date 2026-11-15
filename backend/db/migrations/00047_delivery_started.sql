-- Course démarrée par le livreur (« Glisser pour démarrer ma course », spec 036) : en route vers la
-- boutique. Le statut reste « assigned » jusqu'à l'arrivée.

-- +goose Up
ALTER TABLE deliveries ADD COLUMN started_at timestamptz;

-- +goose Down
ALTER TABLE deliveries DROP COLUMN started_at;
