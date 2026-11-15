-- Suppression de compte : l'adresse de livraison copiée dans les commandes est effacée ; les
-- montants et l'historique restent (traçabilité financière). La contrainte de cohérence d'une
-- livraison accepte désormais une commande dont les données personnelles ont été effacées.

-- +goose Up
ALTER TABLE orders ADD COLUMN personal_data_erased_at timestamptz;

ALTER TABLE orders DROP CONSTRAINT orders_check1;
ALTER TABLE orders ADD CONSTRAINT orders_fulfillment_details_check CHECK (
  (fulfillment = 'pickup' AND vehicle_type IS NULL AND delivery_location IS NULL AND delivery_fee_xof = 0)
  OR (fulfillment = 'delivery' AND vehicle_type IS NOT NULL
      AND (personal_data_erased_at IS NOT NULL
           OR (delivery_location IS NOT NULL AND delivery_address_text IS NOT NULL)))
);

-- +goose Down
ALTER TABLE orders DROP CONSTRAINT orders_fulfillment_details_check;
ALTER TABLE orders ADD CONSTRAINT orders_check1 CHECK (
  (fulfillment = 'pickup' AND vehicle_type IS NULL AND delivery_location IS NULL AND delivery_fee_xof = 0)
  OR (fulfillment = 'delivery' AND vehicle_type IS NOT NULL AND delivery_location IS NOT NULL
      AND delivery_address_text IS NOT NULL)
);
ALTER TABLE orders DROP COLUMN personal_data_erased_at;
