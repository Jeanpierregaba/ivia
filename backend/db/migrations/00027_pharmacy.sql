-- Module pharmacy : alerte médicament (spec 029).
--
-- Le client lance une alerte (photo d'ordonnance, photo de la boîte ou nom saisi) ; elle est
-- diffusée aux pharmacies validées, ouvertes ou de garde, autour de lui. Les réponses sont
-- classées par distance, identités masquées jusqu'au déblocage forfaitaire payé dans l'app. Le
-- client réserve ensuite chez une pharmacie : retrait sur place (obligatoire sur ordonnance) ou
-- livraison par un livreur ivia, payée dans l'app puis reversée à la pharmacie moins la commission.
--
-- Données de santé : photos dans le compartiment privé, lues par URL signée courte par les seules
-- pharmacies sollicitées ; supprimées après la durée de conservation (pharmacy_settings).

-- +goose Up

-- Rôle et app de la pharmacie (contraintes élargies, valeurs existantes inchangées).
ALTER TABLE user_roles DROP CONSTRAINT user_roles_role_check;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_role_check
  CHECK (role IN ('buyer', 'seller', 'driver', 'admin', 'pharmacist'));
ALTER TABLE device_tokens DROP CONSTRAINT device_tokens_app_check;
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_app_check
  CHECK (app IN ('buyer', 'seller', 'driver', 'pharmacy'));
ALTER TABLE notifications DROP CONSTRAINT notifications_app_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_app_check
  CHECK (app IN ('buyer', 'seller', 'driver', 'admin', 'pharmacy'));

-- Une seule ligne de réglages.
CREATE TABLE pharmacy_settings (
  id                      boolean PRIMARY KEY DEFAULT true CHECK (id),
  enabled                 boolean NOT NULL DEFAULT true,
  unlock_fee_xof          bigint NOT NULL DEFAULT 100 CHECK (unlock_fee_xof BETWEEN 0 AND 100000),
  search_radius_m         integer NOT NULL DEFAULT 5000 CHECK (search_radius_m BETWEEN 500 AND 50000),
  max_radius_m            integer NOT NULL DEFAULT 10000 CHECK (max_radius_m BETWEEN 500 AND 50000),
  target_responses        integer NOT NULL DEFAULT 3 CHECK (target_responses BETWEEN 1 AND 20),
  widen_after_minutes     integer NOT NULL DEFAULT 4 CHECK (widen_after_minutes BETWEEN 1 AND 60),
  response_window_minutes integer NOT NULL DEFAULT 10 CHECK (response_window_minutes BETWEEN 2 AND 120),
  pickup_hold_minutes     integer NOT NULL DEFAULT 120 CHECK (pickup_hold_minutes BETWEEN 15 AND 1440),
  photo_retention_days    integer NOT NULL DEFAULT 30 CHECK (photo_retention_days BETWEEN 1 AND 365),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  CHECK (max_radius_m >= search_radius_m)
);
INSERT INTO pharmacy_settings DEFAULT VALUES;

CREATE TABLE pharmacies (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Le titulaire (compte qui a inscrit la pharmacie) ; une pharmacie par compte.
  owner_id          uuid NOT NULL UNIQUE REFERENCES users (id),
  name              text NOT NULL CHECK (length(name) BETWEEN 2 AND 120),
  license_number    text NOT NULL CHECK (length(license_number) BETWEEN 2 AND 60),
  phone             text NOT NULL CHECK (length(phone) BETWEEN 8 AND 20),
  address_text      text NOT NULL CHECK (length(address_text) BETWEEN 3 AND 300),
  neighborhood_id   uuid REFERENCES neighborhoods (id),
  location          geography(Point, 4326) NOT NULL,
  opening_hours     text NOT NULL DEFAULT '' CHECK (length(opening_hours) <= 300),
  is_open           boolean NOT NULL DEFAULT false,
  on_duty           boolean NOT NULL DEFAULT false,
  review_status     text NOT NULL DEFAULT 'pending_review'
                    CHECK (review_status IN ('pending_review', 'approved', 'rejected')),
  review_note       text NOT NULL DEFAULT '',
  reviewed_at       timestamptz,
  reviewed_by       uuid REFERENCES users (id),
  suspended_at      timestamptz,
  suspension_reason text NOT NULL DEFAULT '',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX pharmacies_reachable_idx ON pharmacies USING gist (location)
  WHERE review_status = 'approved' AND suspended_at IS NULL AND (is_open OR on_duty);
CREATE INDEX pharmacies_review_idx ON pharmacies (review_status, created_at);

-- Pièces du dossier (compartiment privé, URL signée réservée aux admins).
CREATE TABLE pharmacy_documents (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies (id),
  kind        text NOT NULL CHECK (kind IN ('opening_authorization', 'order_registration', 'owner_id', 'other')),
  object_key  text NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX pharmacy_documents_pharmacy_idx ON pharmacy_documents (pharmacy_id, created_at);

CREATE TABLE pharmacy_alerts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id        uuid NOT NULL REFERENCES users (id),
  kind            text NOT NULL CHECK (kind IN ('prescription', 'box_photo', 'name')),
  medicine_name   text NOT NULL DEFAULT '' CHECK (length(medicine_name) <= 120),
  quantity        integer NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 20),
  note            text NOT NULL DEFAULT '' CHECK (length(note) <= 300),
  photo_key       text,
  photo_purged_at timestamptz,
  location        geography(Point, 4326) NOT NULL,
  radius_m        integer NOT NULL CHECK (radius_m > 0),
  status          text NOT NULL DEFAULT 'searching' CHECK (status IN (
                    'searching', 'answered', 'no_response', 'unlocked', 'fulfilled', 'cancelled')),
  search_ends_at  timestamptz NOT NULL,
  widened_at      timestamptz,
  closed_at       timestamptz,
  unlocked_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (kind = 'name' OR photo_key IS NOT NULL OR photo_purged_at IS NOT NULL),
  CHECK (kind <> 'name' OR length(medicine_name) >= 2)
);
CREATE INDEX pharmacy_alerts_buyer_idx ON pharmacy_alerts (buyer_id, created_at DESC);
CREATE INDEX pharmacy_alerts_status_idx ON pharmacy_alerts (status, created_at);
CREATE INDEX pharmacy_alerts_photo_idx ON pharmacy_alerts (closed_at)
  WHERE photo_key IS NOT NULL AND photo_purged_at IS NULL;

-- Pharmacies sollicitées par une alerte.
CREATE TABLE pharmacy_alert_targets (
  alert_id     uuid NOT NULL REFERENCES pharmacy_alerts (id),
  pharmacy_id  uuid NOT NULL REFERENCES pharmacies (id),
  distance_m   integer NOT NULL CHECK (distance_m >= 0),
  status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'responded', 'declined', 'expired')),
  notified_at  timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  PRIMARY KEY (alert_id, pharmacy_id)
);
CREATE INDEX pharmacy_alert_targets_inbox_idx ON pharmacy_alert_targets (pharmacy_id, status, notified_at DESC);

-- Réponse « disponible » d'une pharmacie (le refus reste dans pharmacy_alert_targets).
CREATE TABLE pharmacy_responses (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id              uuid NOT NULL REFERENCES pharmacy_alerts (id),
  pharmacy_id           uuid NOT NULL REFERENCES pharmacies (id),
  product_name          text NOT NULL CHECK (length(product_name) BETWEEN 2 AND 120),
  unit_price_xof        bigint NOT NULL CHECK (unit_price_xof BETWEEN 1 AND 10000000),
  quantity_available    integer NOT NULL CHECK (quantity_available BETWEEN 1 AND 1000),
  prescription_required boolean NOT NULL DEFAULT false,
  note                  text NOT NULL DEFAULT '' CHECK (length(note) <= 300),
  distance_m            integer NOT NULL CHECK (distance_m >= 0),
  -- withdrawn : la pharmacie n'a plus le produit.
  status                text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'withdrawn')),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (alert_id, pharmacy_id)
);
CREATE INDEX pharmacy_responses_alert_idx ON pharmacy_responses (alert_id, distance_m);

CREATE TABLE pharmacy_reservations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id          uuid NOT NULL REFERENCES pharmacy_alerts (id),
  response_id       uuid NOT NULL REFERENCES pharmacy_responses (id),
  pharmacy_id       uuid NOT NULL REFERENCES pharmacies (id),
  buyer_id          uuid NOT NULL REFERENCES users (id),
  fulfillment       text NOT NULL CHECK (fulfillment IN ('pickup', 'delivery')),
  status            text NOT NULL CHECK (status IN (
                      'reserved',          -- retrait : en attente du client à la pharmacie
                      'awaiting_payment',  -- livraison : en attente du paiement dans l'app
                      'paid',              -- livraison : payé, recherche d'un livreur
                      'courier_assigned',  -- livraison : livreur en route vers la pharmacie
                      'picked_up',         -- livraison : médicament récupéré
                      'completed', 'expired', 'cancelled')),
  quantity          integer NOT NULL CHECK (quantity BETWEEN 1 AND 20),
  unit_price_xof    bigint NOT NULL CHECK (unit_price_xof > 0),
  items_xof         bigint NOT NULL CHECK (items_xof > 0),
  delivery_fee_xof  bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_xof >= 0),
  commission_xof    bigint NOT NULL DEFAULT 0 CHECK (commission_xof >= 0),
  total_xof         bigint NOT NULL CHECK (total_xof > 0),
  -- Somme reversée à la pharmacie (livraison payée dans l'app) ; 0 pour un retrait payé sur place.
  pharmacy_due_xof  bigint NOT NULL DEFAULT 0 CHECK (pharmacy_due_xof >= 0),
  -- Code à présenter : à la pharmacie (retrait) ou au livreur (livraison). Jamais journalisé.
  handover_code     text NOT NULL CHECK (handover_code ~ '^[0-9]{6}$'),
  delivery_address  text NOT NULL DEFAULT '' CHECK (length(delivery_address) <= 300),
  delivery_location geography(Point, 4326),
  delivery_instructions text NOT NULL DEFAULT '' CHECK (length(delivery_instructions) <= 300),
  expires_at        timestamptz,
  cancel_reason     text NOT NULL DEFAULT '',
  completed_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CHECK (items_xof = unit_price_xof * quantity),
  CHECK (total_xof = items_xof + delivery_fee_xof),
  CHECK (fulfillment = 'pickup' OR delivery_location IS NOT NULL)
);
-- Une seule réservation en cours par alerte.
CREATE UNIQUE INDEX pharmacy_reservations_one_active_per_alert ON pharmacy_reservations (alert_id)
  WHERE status IN ('reserved', 'awaiting_payment', 'paid', 'courier_assigned', 'picked_up');
CREATE INDEX pharmacy_reservations_pharmacy_idx ON pharmacy_reservations (pharmacy_id, created_at DESC);
CREATE INDEX pharmacy_reservations_buyer_idx ON pharmacy_reservations (buyer_id, created_at DESC);

-- Paiements via l'agrégateur Mobile Money (même prestataire que les commandes, ADR 0007).
-- Les événements reçus sont enregistrés dans payment_events (référence « ivh_… »).
CREATE TABLE pharmacy_payments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purpose        text NOT NULL CHECK (purpose IN ('unlock', 'order')),
  alert_id       uuid NOT NULL REFERENCES pharmacy_alerts (id),
  reservation_id uuid REFERENCES pharmacy_reservations (id),
  buyer_id       uuid NOT NULL REFERENCES users (id),
  provider       text NOT NULL,
  reference      text NOT NULL UNIQUE,
  provider_ref   text,
  amount_xof     bigint NOT NULL CHECK (amount_xof > 0),
  currency       text NOT NULL DEFAULT 'XOF',
  operator       text NOT NULL CHECK (operator IN ('flooz', 'tmoney')),
  payer_phone    text NOT NULL,
  status         text NOT NULL DEFAULT 'pending' CHECK (status IN (
                   'pending', 'succeeded', 'failed', 'expired', 'refund_pending', 'refunded')),
  failure_reason text NOT NULL DEFAULT '',
  succeeded_at   timestamptz,
  refund_reference text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CHECK ((purpose = 'order') = (reservation_id IS NOT NULL))
);
CREATE UNIQUE INDEX pharmacy_payments_one_pending_unlock ON pharmacy_payments (alert_id)
  WHERE purpose = 'unlock' AND status = 'pending';
CREATE UNIQUE INDEX pharmacy_payments_one_pending_order ON pharmacy_payments (reservation_id)
  WHERE purpose = 'order' AND status = 'pending';
CREATE INDEX pharmacy_payments_status_idx ON pharmacy_payments (status, created_at);
CREATE INDEX pharmacy_payments_buyer_idx ON pharmacy_payments (buyer_id, created_at DESC);

-- Courses des livreurs ivia (propositions et missions), à part des livraisons de commandes.
CREATE TABLE pharmacy_courier_offers (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES pharmacy_reservations (id),
  driver_id      uuid NOT NULL REFERENCES drivers (user_id),
  status         text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  distance_m     integer NOT NULL CHECK (distance_m >= 0),
  expires_at     timestamptz NOT NULL,
  responded_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX pharmacy_courier_offers_one_pending_per_reservation ON pharmacy_courier_offers (reservation_id)
  WHERE status = 'pending';
CREATE UNIQUE INDEX pharmacy_courier_offers_one_pending_per_driver ON pharmacy_courier_offers (driver_id)
  WHERE status = 'pending';

CREATE TABLE pharmacy_deliveries (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES pharmacy_reservations (id),
  driver_id      uuid NOT NULL REFERENCES drivers (user_id),
  offer_id       uuid REFERENCES pharmacy_courier_offers (id),
  status         text NOT NULL DEFAULT 'assigned'
                 CHECK (status IN ('assigned', 'picked_up', 'delivered', 'cancelled')),
  fee_xof        bigint NOT NULL CHECK (fee_xof >= 0),
  assigned_at    timestamptz NOT NULL DEFAULT now(),
  picked_up_at   timestamptz,
  delivered_at   timestamptz,
  ended_at       timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX pharmacy_deliveries_one_active_per_reservation ON pharmacy_deliveries (reservation_id)
  WHERE status IN ('assigned', 'picked_up');
CREATE UNIQUE INDEX pharmacy_deliveries_one_active_per_driver ON pharmacy_deliveries (driver_id)
  WHERE status IN ('assigned', 'picked_up');

-- Reversements aux pharmacies (virement Mobile Money ou bancaire fait par l'admin). Ajout seul.
CREATE TABLE pharmacy_payouts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id uuid NOT NULL REFERENCES pharmacies (id),
  amount_xof  bigint NOT NULL CHECK (amount_xof > 0),
  reference   text NOT NULL CHECK (length(reference) BETWEEN 2 AND 100),
  note        text NOT NULL DEFAULT '' CHECK (length(note) <= 300),
  paid_by     uuid NOT NULL REFERENCES users (id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX pharmacy_payouts_pharmacy_idx ON pharmacy_payouts (pharmacy_id, created_at DESC);
CREATE TRIGGER pharmacy_payouts_append_only
  BEFORE UPDATE OR DELETE ON pharmacy_payouts
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();

-- +goose Down
DROP TABLE pharmacy_payouts;
DROP TABLE pharmacy_deliveries;
DROP TABLE pharmacy_courier_offers;
DROP TABLE pharmacy_payments;
DROP TABLE pharmacy_reservations;
DROP TABLE pharmacy_responses;
DROP TABLE pharmacy_alert_targets;
DROP TABLE pharmacy_alerts;
DROP TABLE pharmacy_documents;
DROP TABLE pharmacies;
DROP TABLE pharmacy_settings;
ALTER TABLE notifications DROP CONSTRAINT notifications_app_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_app_check
  CHECK (app IN ('buyer', 'seller', 'driver', 'admin'));
ALTER TABLE device_tokens DROP CONSTRAINT device_tokens_app_check;
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_app_check
  CHECK (app IN ('buyer', 'seller', 'driver'));
ALTER TABLE user_roles DROP CONSTRAINT user_roles_role_check;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_role_check
  CHECK (role IN ('buyer', 'seller', 'driver', 'admin'));
