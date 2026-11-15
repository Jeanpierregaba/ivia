-- Module delivery : livreurs, positions, propositions de mission et missions.

-- +goose Up
CREATE TABLE drivers (
  user_id             uuid PRIMARY KEY REFERENCES users (id),
  review_status       text NOT NULL DEFAULT 'pending_review'
                      CHECK (review_status IN ('pending_review', 'approved', 'rejected')),
  review_note         text NOT NULL DEFAULT '',
  reviewed_at         timestamptz,
  reviewed_by         uuid REFERENCES users (id),
  suspended_at        timestamptz,
  suspension_reason   text NOT NULL DEFAULT '',
  availability        text NOT NULL DEFAULT 'offline' CHECK (availability IN ('offline', 'available', 'busy')),
  vehicle_type        text NOT NULL CHECK (vehicle_type IN ('motorbike', 'car')),
  vehicle_plate       text NOT NULL DEFAULT '' CHECK (length(vehicle_plate) <= 20),
  vehicle_description text NOT NULL DEFAULT '' CHECK (length(vehicle_description) <= 200),
  last_location       geography(Point, 4326),
  last_location_at    timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX drivers_available_idx ON drivers USING gist (last_location)
  WHERE availability = 'available' AND review_status = 'approved' AND suspended_at IS NULL;

CREATE TABLE driver_documents (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id  uuid NOT NULL REFERENCES drivers (user_id),
  kind       text NOT NULL CHECK (kind IN ('id_card', 'driving_license', 'vehicle_registration', 'photo', 'other')),
  object_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX driver_documents_driver_idx ON driver_documents (driver_id);

-- Positions brutes : conservées 30 jours (purge par tâche de fond).
CREATE TABLE driver_positions (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  driver_id   uuid NOT NULL REFERENCES drivers (user_id),
  location    geography(Point, 4326) NOT NULL,
  accuracy_m  integer CHECK (accuracy_m >= 0),
  recorded_at timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX driver_positions_driver_idx ON driver_positions (driver_id, created_at DESC);
CREATE INDEX driver_positions_created_at_idx ON driver_positions (created_at);

-- Suivi de la recherche d'un livreur pour une commande (alerte admin).
CREATE TABLE assignment_requests (
  order_id     uuid PRIMARY KEY REFERENCES orders (id),
  started_at   timestamptz NOT NULL DEFAULT now(),
  offers_count integer NOT NULL DEFAULT 0,
  alerted_at   timestamptz,
  closed_at    timestamptz
);

CREATE TABLE delivery_offers (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id           uuid NOT NULL REFERENCES orders (id),
  driver_id          uuid NOT NULL REFERENCES drivers (user_id),
  status             text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  distance_to_shop_m integer NOT NULL CHECK (distance_to_shop_m >= 0),
  expires_at         timestamptz NOT NULL,
  responded_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now()
);
-- Une seule proposition en attente par commande et par livreur.
CREATE UNIQUE INDEX delivery_offers_one_pending_per_order ON delivery_offers (order_id) WHERE status = 'pending';
CREATE UNIQUE INDEX delivery_offers_one_pending_per_driver ON delivery_offers (driver_id) WHERE status = 'pending';
CREATE INDEX delivery_offers_order_driver_idx ON delivery_offers (order_id, driver_id);

CREATE TABLE deliveries (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id            uuid NOT NULL REFERENCES orders (id),
  driver_id           uuid NOT NULL REFERENCES drivers (user_id),
  offer_id            uuid REFERENCES delivery_offers (id),
  status              text NOT NULL DEFAULT 'assigned' CHECK (status IN (
                        'assigned', 'at_shop', 'picked_up', 'at_customer', 'delivered',
                        'returning', 'returned', 'withdrawn', 'cancelled')),
  fee_xof             bigint NOT NULL CHECK (fee_xof >= 0),
  assigned_at         timestamptz NOT NULL DEFAULT now(),
  arrived_shop_at     timestamptz,
  picked_up_at        timestamptz,
  arrived_customer_at timestamptz,
  delivered_at        timestamptz,
  failed_at           timestamptz,
  failure_reason      text NOT NULL DEFAULT '',
  call_attempts       integer NOT NULL DEFAULT 0 CHECK (call_attempts >= 0),
  ended_at            timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
-- Garanties de concurrence : jamais deux livreurs actifs sur une commande, une mission à la fois par livreur.
CREATE UNIQUE INDEX deliveries_one_active_per_order ON deliveries (order_id)
  WHERE status IN ('assigned', 'at_shop', 'picked_up', 'at_customer', 'returning');
CREATE UNIQUE INDEX deliveries_one_active_per_driver ON deliveries (driver_id)
  WHERE status IN ('assigned', 'at_shop', 'picked_up', 'at_customer', 'returning');
CREATE INDEX deliveries_driver_idx ON deliveries (driver_id, created_at DESC);
CREATE INDEX deliveries_delivered_at_idx ON deliveries (delivered_at) WHERE delivered_at IS NOT NULL;

-- +goose Down
DROP TABLE deliveries;
DROP TABLE delivery_offers;
DROP TABLE assignment_requests;
DROP TABLE driver_positions;
DROP TABLE driver_documents;
DROP TABLE drivers;
