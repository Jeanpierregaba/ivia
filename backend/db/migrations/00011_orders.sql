-- Module orders : commandes, lignes (copie du produit au moment de l'achat) et historique des statuts.

-- +goose Up
CREATE TABLE orders (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Numéro lisible pour le support (affiché « IV-000123 »).
  number                bigint NOT NULL GENERATED ALWAYS AS IDENTITY UNIQUE,
  buyer_id              uuid NOT NULL REFERENCES users (id),
  shop_id               uuid NOT NULL REFERENCES shops (id),
  status                text NOT NULL CHECK (status IN (
                          'pending_payment', 'expired', 'awaiting_seller', 'accepted', 'preparing',
                          'ready_for_pickup', 'awaiting_driver', 'driver_assigned', 'picked_up',
                          'delivered', 'delivery_failed', 'returned_to_shop', 'completed',
                          'cancelled', 'refunded')),
  fulfillment           text NOT NULL CHECK (fulfillment IN ('pickup', 'delivery')),
  vehicle_type          text CHECK (vehicle_type IN ('motorbike', 'car')),
  parcel_size           text NOT NULL CHECK (parcel_size IN ('small', 'medium', 'large')),
  subtotal_xof          bigint NOT NULL CHECK (subtotal_xof > 0),
  delivery_fee_xof      bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_xof >= 0),
  total_xof             bigint NOT NULL,
  commission_rate_bp    integer NOT NULL CHECK (commission_rate_bp BETWEEN 0 AND 10000),
  commission_xof        bigint NOT NULL CHECK (commission_xof >= 0),
  delivery_distance_m   integer CHECK (delivery_distance_m >= 0),
  delivery_address_text text,
  delivery_neighborhood text,
  delivery_location     geography(Point, 4326),
  delivery_instructions text,
  -- Code de remise à 4 chiffres, affiché à l'acheteur (stocké en clair, voir ARCHITECTURE).
  handover_code         text NOT NULL CHECK (handover_code ~ '^[0-9]{4}$'),
  handover_attempts     integer NOT NULL DEFAULT 0 CHECK (handover_attempts >= 0),
  stock_released        boolean NOT NULL DEFAULT false,
  -- Idempotence de la création : une même requête rejouée ne crée pas deux commandes.
  client_request_id     uuid,
  cancel_reason         text NOT NULL DEFAULT '',
  -- Montant à rembourser quand la commande entre dans la file de remboursement.
  refund_due_xof        bigint NOT NULL DEFAULT 0 CHECK (refund_due_xof >= 0),
  payment_deadline_at   timestamptz NOT NULL,
  seller_deadline_at    timestamptz,
  paid_at               timestamptz,
  accepted_at           timestamptz,
  ready_at              timestamptz,
  picked_up_at          timestamptz,
  completed_at          timestamptz,
  cancelled_at          timestamptz,
  refunded_at           timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CHECK (total_xof = subtotal_xof + delivery_fee_xof),
  CHECK (
    (fulfillment = 'pickup' AND vehicle_type IS NULL AND delivery_location IS NULL AND delivery_fee_xof = 0)
    OR (fulfillment = 'delivery' AND vehicle_type IS NOT NULL AND delivery_location IS NOT NULL
        AND delivery_address_text IS NOT NULL)
  ),
  UNIQUE (buyer_id, client_request_id)
);
CREATE INDEX orders_buyer_idx ON orders (buyer_id, created_at DESC);
CREATE INDEX orders_shop_idx ON orders (shop_id, status, created_at DESC);
CREATE INDEX orders_status_idx ON orders (status, created_at DESC);
CREATE INDEX orders_completed_at_idx ON orders (shop_id, completed_at) WHERE completed_at IS NOT NULL;

CREATE TABLE order_items (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       uuid NOT NULL REFERENCES orders (id),
  product_id     uuid NOT NULL REFERENCES products (id),
  product_name   text NOT NULL,
  unit_price_xof bigint NOT NULL CHECK (unit_price_xof > 0),
  quantity       integer NOT NULL CHECK (quantity BETWEEN 1 AND 99),
  line_total_xof bigint NOT NULL,
  parcel_size    text NOT NULL CHECK (parcel_size IN ('small', 'medium', 'large')),
  stock_mode     text NOT NULL CHECK (stock_mode IN ('tracked', 'untracked')),
  CHECK (line_total_xof = unit_price_xof * quantity),
  UNIQUE (order_id, product_id)
);

CREATE TABLE order_status_events (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id    uuid NOT NULL REFERENCES orders (id),
  from_status text,
  to_status   text NOT NULL,
  actor_type  text NOT NULL CHECK (actor_type IN ('buyer', 'seller', 'driver', 'admin', 'system')),
  actor_id    uuid REFERENCES users (id),
  reason      text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX order_status_events_order_idx ON order_status_events (order_id, id);

CREATE TRIGGER order_status_events_append_only
  BEFORE UPDATE OR DELETE ON order_status_events
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
CREATE TRIGGER order_status_events_no_truncate
  BEFORE TRUNCATE ON order_status_events
  FOR EACH STATEMENT EXECUTE FUNCTION forbid_mutation();

-- +goose Down
DROP TABLE order_status_events;
DROP TABLE order_items;
DROP TABLE orders;
