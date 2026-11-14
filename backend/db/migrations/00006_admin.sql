-- Module admin : paramètres de la plateforme et journal des actions admin (ajout seul).

-- +goose Up
CREATE TABLE settings (
  -- Une seule ligne.
  id                              boolean PRIMARY KEY DEFAULT true CHECK (id),
  -- Commission en points de base (1000 = 10 %) : pas de nombre à virgule.
  commission_rate_bp              integer NOT NULL CHECK (commission_rate_bp BETWEEN 0 AND 10000),
  motorbike_base_fee_xof          bigint  NOT NULL CHECK (motorbike_base_fee_xof >= 0),
  motorbike_per_km_xof            bigint  NOT NULL CHECK (motorbike_per_km_xof >= 0),
  car_base_fee_xof                bigint  NOT NULL CHECK (car_base_fee_xof >= 0),
  car_per_km_xof                  bigint  NOT NULL CHECK (car_per_km_xof >= 0),
  -- Coefficient appliqué à la distance à vol d'oiseau, en pourcentage (130 = × 1,3).
  distance_coefficient_pct        integer NOT NULL CHECK (distance_coefficient_pct BETWEEN 100 AND 300),
  payment_timeout_minutes         integer NOT NULL CHECK (payment_timeout_minutes BETWEEN 5 AND 120),
  seller_response_timeout_minutes integer NOT NULL CHECK (seller_response_timeout_minutes BETWEEN 5 AND 120),
  driver_offer_timeout_seconds    integer NOT NULL CHECK (driver_offer_timeout_seconds BETWEEN 15 AND 300),
  assignment_max_offers           integer NOT NULL CHECK (assignment_max_offers BETWEEN 1 AND 50),
  assignment_alert_minutes        integer NOT NULL CHECK (assignment_alert_minutes BETWEEN 1 AND 240),
  updated_at                      timestamptz NOT NULL DEFAULT now(),
  updated_by                      uuid REFERENCES users (id)
);

-- Valeurs de départ, modifiables par l'admin (PATCH /v1/admin/settings).
INSERT INTO settings (
  commission_rate_bp,
  motorbike_base_fee_xof, motorbike_per_km_xof,
  car_base_fee_xof, car_per_km_xof,
  distance_coefficient_pct,
  payment_timeout_minutes, seller_response_timeout_minutes,
  driver_offer_timeout_seconds, assignment_max_offers, assignment_alert_minutes
) VALUES (1000, 500, 150, 1500, 300, 130, 15, 15, 45, 5, 20);

CREATE TABLE admin_audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- NULL : action du système ou de la ligne de commande d'administration.
  admin_id    uuid REFERENCES users (id),
  action      text NOT NULL,
  target_type text NOT NULL,
  target_id   text NOT NULL,
  before      jsonb,
  after       jsonb,
  reason      text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_audit_log_target_idx ON admin_audit_log (target_type, target_id, created_at DESC);
CREATE INDEX admin_audit_log_admin_idx ON admin_audit_log (admin_id, created_at DESC);
CREATE INDEX admin_audit_log_created_at_idx ON admin_audit_log (created_at DESC);

CREATE TRIGGER admin_audit_log_append_only
  BEFORE UPDATE OR DELETE ON admin_audit_log
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER admin_audit_log_no_truncate
  BEFORE TRUNCATE ON admin_audit_log
  FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

-- +goose Down
DROP TABLE admin_audit_log;
DROP TABLE settings;
