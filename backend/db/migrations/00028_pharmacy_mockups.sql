-- Module pharmacy : alignement sur les maquettes de l'app acheteur (P01 à P14).
--
-- Changements de règles (maquettes « Alerte médicament : parcours client ») :
--   - une alerte combine plusieurs produits saisis (nom, forme, quantité) et plusieurs photos
--     (pages d'ordonnance, boîtes), avec « générique accepté » et une précision ;
--   - le client choisit le rayon (2, 5 ou 10 km, réglables) ; l'alerte part aux pharmacies de
--     garde (planning en vigueur, 24 h/24, ou déclarées ouvertes / de garde) ;
--   - la pharmacie répond ligne par ligne (disponible ou non, prix) ;
--   - le forfait débloque UNE pharmacie ; débloquer une autre se paie à nouveau ; le déblocage met
--     les produits de côté (1 h) avec un code de retrait à 4 chiffres ;
--   - « Livreur ivia » : la recherche du livreur part tout de suite (les plus proches d'abord) ;
--     le client paie produits et livraison une fois qu'un livreur a accepté ; possible même sur
--     ordonnance : le livreur vérifie l'original à la remise ;
--   - pas de commission sur les médicaments par défaut : ivia est rémunéré par le forfait de déblocage
--     (taux réglable, 0 par défaut) ;
--   - photos supprimées 24 h après l'alerte ; réponses ouvertes 20 min.
--
-- Migration additive : les colonnes de 00027 devenues inutiles restent en place (non lues).

-- +goose Up

ALTER TABLE pharmacy_settings
  ADD COLUMN radius_options_m      integer[] NOT NULL DEFAULT '{2000,5000,10000}',
  ADD COLUMN photo_retention_hours integer NOT NULL DEFAULT 24 CHECK (photo_retention_hours BETWEEN 1 AND 8760),
  ADD COLUMN auto_widen            boolean NOT NULL DEFAULT false,
  ADD COLUMN product_commission_bp integer NOT NULL DEFAULT 0 CHECK (product_commission_bp BETWEEN 0 AND 5000);
ALTER TABLE pharmacy_settings ALTER COLUMN response_window_minutes SET DEFAULT 20;
ALTER TABLE pharmacy_settings ALTER COLUMN pickup_hold_minutes SET DEFAULT 60;
UPDATE pharmacy_settings SET response_window_minutes = 20 WHERE response_window_minutes = 10;
UPDATE pharmacy_settings SET pickup_hold_minutes = 60 WHERE pickup_hold_minutes = 120;

-- Pharmacies ouvertes jour et nuit, et planning de garde (publié par l'Ordre, saisi par l'admin).
ALTER TABLE pharmacies ADD COLUMN open_24h boolean NOT NULL DEFAULT false;
DROP INDEX pharmacies_reachable_idx;
CREATE INDEX pharmacies_approved_location_idx ON pharmacies USING gist (location)
  WHERE review_status = 'approved' AND suspended_at IS NULL;

CREATE TABLE pharmacy_duty_shifts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies (id),
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  created_by  uuid NOT NULL REFERENCES users (id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at AND ends_at - starts_at <= interval '8 days')
);
CREATE INDEX pharmacy_duty_shifts_pharmacy_idx ON pharmacy_duty_shifts (pharmacy_id, ends_at DESC);
CREATE INDEX pharmacy_duty_shifts_window_idx ON pharmacy_duty_shifts (starts_at, ends_at);

-- Base des médicaments (suggestions de saisie) ; un produit absent reste saisissable librement.
CREATE TABLE medicines (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name              text NOT NULL CHECK (length(name) BETWEEN 2 AND 120),
  dosage            text NOT NULL DEFAULT '' CHECK (length(dosage) <= 60),
  form              text NOT NULL DEFAULT '' CHECK (length(form) <= 60),
  active_ingredient text NOT NULL DEFAULT '' CHECK (length(active_ingredient) <= 120),
  is_active         boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (name, dosage, form)
);
CREATE INDEX medicines_search_trgm_idx ON medicines
  USING gin (immutable_unaccent(lower(name || ' ' || dosage || ' ' || active_ingredient)) gin_trgm_ops);

INSERT INTO medicines (name, dosage, form, active_ingredient) VALUES
  ('Paracétamol', '500 mg', 'Comprimés', 'Paracétamol'),
  ('Paracétamol', '1000 mg', 'Comprimés', 'Paracétamol'),
  ('Paracétamol', '120 mg/5 ml', 'Sirop', 'Paracétamol'),
  ('Amoxicilline', '500 mg', 'Gélules', 'Amoxicilline'),
  ('Amoxicilline', '1 g', 'Comprimés', 'Amoxicilline'),
  ('Amoxicilline + ac. clavulanique', '1 g', 'Comprimés', 'Amoxicilline, acide clavulanique'),
  ('Ibuprofène', '400 mg', 'Comprimés', 'Ibuprofène'),
  ('Artéméther + luméfantrine', '20/120 mg', 'Comprimés', 'Artéméther, luméfantrine'),
  ('Artésunate + amodiaquine', '100/270 mg', 'Comprimés', 'Artésunate, amodiaquine'),
  ('Métronidazole', '500 mg', 'Comprimés', 'Métronidazole'),
  ('Ciprofloxacine', '500 mg', 'Comprimés', 'Ciprofloxacine'),
  ('Cotrimoxazole', '480 mg', 'Comprimés', 'Sulfaméthoxazole, triméthoprime'),
  ('Oméprazole', '20 mg', 'Gélules', 'Oméprazole'),
  ('Sels de réhydratation orale', '', 'Sachets', 'Sels de réhydratation'),
  ('Zinc', '20 mg', 'Comprimés dispersibles', 'Sulfate de zinc'),
  ('Salbutamol', '100 µg', 'Aérosol', 'Salbutamol'),
  ('Amlodipine', '5 mg', 'Comprimés', 'Amlodipine'),
  ('Metformine', '500 mg', 'Comprimés', 'Metformine'),
  ('Loratadine', '10 mg', 'Comprimés', 'Loratadine'),
  ('Fer + acide folique', '', 'Comprimés', 'Fer, acide folique');

-- Une alerte combine des produits saisis et des photos.
ALTER TABLE pharmacy_alerts DROP CONSTRAINT IF EXISTS pharmacy_alerts_kind_check;
ALTER TABLE pharmacy_alerts DROP CONSTRAINT IF EXISTS pharmacy_alerts_check;
ALTER TABLE pharmacy_alerts DROP CONSTRAINT IF EXISTS pharmacy_alerts_check1;
ALTER TABLE pharmacy_alerts ADD CONSTRAINT pharmacy_alerts_kind_check
  CHECK (kind IN ('prescription', 'box_photo', 'name', 'mixed'));
ALTER TABLE pharmacy_alerts
  ADD COLUMN generic_accepted boolean NOT NULL DEFAULT false,
  ADD COLUMN relaunched_from  uuid REFERENCES pharmacy_alerts (id);

CREATE TABLE pharmacy_alert_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id    uuid NOT NULL REFERENCES pharmacy_alerts (id),
  position    integer NOT NULL CHECK (position BETWEEN 1 AND 20),
  medicine_id uuid REFERENCES medicines (id),
  name        text NOT NULL CHECK (length(name) BETWEEN 2 AND 160),
  form        text NOT NULL DEFAULT '' CHECK (length(form) <= 60),
  quantity    integer NOT NULL CHECK (quantity BETWEEN 1 AND 20),
  UNIQUE (alert_id, position)
);

CREATE TABLE pharmacy_alert_photos (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id   uuid NOT NULL REFERENCES pharmacy_alerts (id),
  kind       text NOT NULL CHECK (kind IN ('prescription', 'box')),
  position   integer NOT NULL CHECK (position BETWEEN 1 AND 10),
  object_key text UNIQUE,
  purged_at  timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (alert_id, position),
  CHECK (object_key IS NOT NULL OR purged_at IS NOT NULL)
);
CREATE INDEX pharmacy_alert_photos_live_idx ON pharmacy_alert_photos (created_at) WHERE object_key IS NOT NULL;

-- « Ont vu » : la pharmacie a ouvert l'alerte.
ALTER TABLE pharmacy_alert_targets ADD COLUMN seen_at timestamptz;

-- Réponse ligne par ligne ; déblocage par réponse.
ALTER TABLE pharmacy_responses
  ADD COLUMN total_xof       bigint NOT NULL DEFAULT 0 CHECK (total_xof >= 0),
  ADD COLUMN available_count integer NOT NULL DEFAULT 0 CHECK (available_count >= 0),
  ADD COLUMN line_count      integer NOT NULL DEFAULT 0 CHECK (line_count >= 0),
  ADD COLUMN unlocked_at     timestamptz;

CREATE TABLE pharmacy_response_lines (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  response_id           uuid NOT NULL REFERENCES pharmacy_responses (id) ON DELETE CASCADE,
  position              integer NOT NULL CHECK (position BETWEEN 1 AND 30),
  alert_item_id         uuid REFERENCES pharmacy_alert_items (id),
  name                  text NOT NULL CHECK (length(name) BETWEEN 2 AND 160),
  quantity              integer NOT NULL CHECK (quantity BETWEEN 1 AND 100),
  unit_price_xof        bigint NOT NULL CHECK (unit_price_xof BETWEEN 0 AND 10000000),
  available             boolean NOT NULL,
  prescription_required boolean NOT NULL DEFAULT false,
  UNIQUE (response_id, position),
  CHECK (NOT available OR unit_price_xof > 0)
);

ALTER TABLE pharmacy_payments ADD COLUMN response_id uuid REFERENCES pharmacy_responses (id);
DROP INDEX pharmacy_payments_one_pending_unlock;
CREATE UNIQUE INDEX pharmacy_payments_one_pending_unlock_per_response ON pharmacy_payments (response_id)
  WHERE purpose = 'unlock' AND status = 'pending';

-- Réservation créée au déblocage (mise de côté), une par réponse débloquée.
ALTER TABLE pharmacy_reservations DROP CONSTRAINT IF EXISTS pharmacy_reservations_handover_code_check;
ALTER TABLE pharmacy_reservations ADD CONSTRAINT pharmacy_reservations_handover_code_check
  CHECK (handover_code ~ '^[0-9]{4,6}$');
-- courier_search : livraison choisie, recherche d'un livreur avant le paiement.
ALTER TABLE pharmacy_reservations DROP CONSTRAINT pharmacy_reservations_status_check;
ALTER TABLE pharmacy_reservations ADD CONSTRAINT pharmacy_reservations_status_check CHECK (status IN (
  'reserved', 'courier_search', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up',
  'completed', 'expired', 'cancelled'));
DROP INDEX pharmacy_reservations_one_active_per_alert;
CREATE UNIQUE INDEX pharmacy_reservations_one_active_per_response ON pharmacy_reservations (response_id)
  WHERE status IN ('reserved', 'courier_search', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up');
ALTER TABLE pharmacy_reservations
  ADD COLUMN number                bigint GENERATED BY DEFAULT AS IDENTITY,
  ADD COLUMN unlock_payment_id     uuid REFERENCES pharmacy_payments (id),
  ADD COLUMN prescription_required boolean NOT NULL DEFAULT false,
  ADD COLUMN paid_at               timestamptz,
  ADD COLUMN prepared_at           timestamptz;
CREATE UNIQUE INDEX pharmacy_reservations_number_idx ON pharmacy_reservations (number);

-- Remise d'un médicament sur ordonnance : le livreur atteste avoir vu l'original.
ALTER TABLE pharmacy_deliveries ADD COLUMN prescription_checked boolean NOT NULL DEFAULT false;

-- +goose Down
ALTER TABLE pharmacy_deliveries DROP COLUMN prescription_checked;
DROP INDEX pharmacy_reservations_number_idx;
ALTER TABLE pharmacy_reservations
  DROP COLUMN prepared_at, DROP COLUMN paid_at, DROP COLUMN prescription_required,
  DROP COLUMN unlock_payment_id, DROP COLUMN number;
DROP INDEX pharmacy_reservations_one_active_per_response;
CREATE UNIQUE INDEX pharmacy_reservations_one_active_per_alert ON pharmacy_reservations (alert_id)
  WHERE status IN ('reserved', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up');
ALTER TABLE pharmacy_reservations DROP CONSTRAINT pharmacy_reservations_handover_code_check;
ALTER TABLE pharmacy_reservations ADD CONSTRAINT pharmacy_reservations_handover_code_check
  CHECK (handover_code ~ '^[0-9]{6}$') NOT VALID;
ALTER TABLE pharmacy_reservations DROP CONSTRAINT pharmacy_reservations_status_check;
ALTER TABLE pharmacy_reservations ADD CONSTRAINT pharmacy_reservations_status_check CHECK (status IN (
  'reserved', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up', 'completed', 'expired', 'cancelled')) NOT VALID;
DROP INDEX pharmacy_payments_one_pending_unlock_per_response;
CREATE UNIQUE INDEX pharmacy_payments_one_pending_unlock ON pharmacy_payments (alert_id)
  WHERE purpose = 'unlock' AND status = 'pending';
ALTER TABLE pharmacy_payments DROP COLUMN response_id;
DROP TABLE pharmacy_response_lines;
ALTER TABLE pharmacy_responses
  DROP COLUMN unlocked_at, DROP COLUMN line_count, DROP COLUMN available_count, DROP COLUMN total_xof;
ALTER TABLE pharmacy_alert_targets DROP COLUMN seen_at;
DROP TABLE pharmacy_alert_photos;
DROP TABLE pharmacy_alert_items;
ALTER TABLE pharmacy_alerts DROP COLUMN relaunched_from, DROP COLUMN generic_accepted;
ALTER TABLE pharmacy_alerts DROP CONSTRAINT pharmacy_alerts_kind_check;
ALTER TABLE pharmacy_alerts ADD CONSTRAINT pharmacy_alerts_kind_check
  CHECK (kind IN ('prescription', 'box_photo', 'name')) NOT VALID;
DROP TABLE medicines;
DROP TABLE pharmacy_duty_shifts;
DROP INDEX pharmacies_approved_location_idx;
CREATE INDEX pharmacies_reachable_idx ON pharmacies USING gist (location)
  WHERE review_status = 'approved' AND suspended_at IS NULL AND (is_open OR on_duty);
ALTER TABLE pharmacies DROP COLUMN open_24h;
ALTER TABLE pharmacy_settings ALTER COLUMN pickup_hold_minutes SET DEFAULT 120;
ALTER TABLE pharmacy_settings ALTER COLUMN response_window_minutes SET DEFAULT 10;
ALTER TABLE pharmacy_settings DROP COLUMN product_commission_bp, DROP COLUMN auto_widen, DROP COLUMN photo_retention_hours, DROP COLUMN radius_options_m;
