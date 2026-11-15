-- Course pharmacie : arrivée à la pharmacie et chez le client, client injoignable puis retour des
-- produits à la pharmacie (décision du 2026-11-12) : le client est remboursé de ses produits, les
-- frais de livraison restent acquis, et les espèces avancées par le livreur lui sont dues.

-- +goose Up
ALTER TABLE pharmacy_deliveries DROP CONSTRAINT pharmacy_deliveries_status_check;
ALTER TABLE pharmacy_deliveries ADD CONSTRAINT pharmacy_deliveries_status_check
  CHECK (status IN ('assigned', 'picked_up', 'returning', 'returned', 'delivered', 'cancelled'));
ALTER TABLE pharmacy_deliveries
  ADD COLUMN arrived_pharmacy_at timestamptz,
  ADD COLUMN arrived_customer_at timestamptz,
  ADD COLUMN failed_at           timestamptz,
  ADD COLUMN failure_reason      text NOT NULL DEFAULT '' CHECK (length(failure_reason) <= 300),
  ADD COLUMN call_attempts       integer NOT NULL DEFAULT 0 CHECK (call_attempts >= 0),
  ADD COLUMN returned_at         timestamptz;

-- Le retour fait partie de la course : le livreur reste occupé jusqu'à la pharmacie.
DROP INDEX pharmacy_deliveries_one_active_per_reservation;
DROP INDEX pharmacy_deliveries_one_active_per_driver;
CREATE UNIQUE INDEX pharmacy_deliveries_one_active_per_reservation ON pharmacy_deliveries (reservation_id)
  WHERE status IN ('assigned', 'picked_up', 'returning');
CREATE UNIQUE INDEX pharmacy_deliveries_one_active_per_driver ON pharmacy_deliveries (driver_id)
  WHERE status IN ('assigned', 'picked_up', 'returning');

-- Remboursement partiel (produits sans les frais de livraison) ; NULL : montant payé en entier.
ALTER TABLE pharmacy_payments
  ADD COLUMN refund_amount_xof bigint CHECK (refund_amount_xof > 0 AND refund_amount_xof <= amount_xof);

-- +goose Down
ALTER TABLE pharmacy_payments DROP COLUMN refund_amount_xof;
DROP INDEX pharmacy_deliveries_one_active_per_reservation;
DROP INDEX pharmacy_deliveries_one_active_per_driver;
UPDATE pharmacy_deliveries SET status = 'cancelled' WHERE status IN ('returning', 'returned');
CREATE UNIQUE INDEX pharmacy_deliveries_one_active_per_reservation ON pharmacy_deliveries (reservation_id)
  WHERE status IN ('assigned', 'picked_up');
CREATE UNIQUE INDEX pharmacy_deliveries_one_active_per_driver ON pharmacy_deliveries (driver_id)
  WHERE status IN ('assigned', 'picked_up');
ALTER TABLE pharmacy_deliveries
  DROP COLUMN returned_at, DROP COLUMN call_attempts, DROP COLUMN failure_reason, DROP COLUMN failed_at,
  DROP COLUMN arrived_customer_at, DROP COLUMN arrived_pharmacy_at;
ALTER TABLE pharmacy_deliveries DROP CONSTRAINT pharmacy_deliveries_status_check;
ALTER TABLE pharmacy_deliveries ADD CONSTRAINT pharmacy_deliveries_status_check
  CHECK (status IN ('assigned', 'picked_up', 'delivered', 'cancelled'));
