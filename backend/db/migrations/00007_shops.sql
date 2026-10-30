-- Module shops : boutiques et leur validation par l'admin.

-- +goose Up
CREATE TABLE shops (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id         uuid NOT NULL REFERENCES users (id),
  name             text NOT NULL CHECK (length(name) BETWEEN 2 AND 100),
  description      text NOT NULL DEFAULT '' CHECK (length(description) <= 2000),
  phone            text NOT NULL CHECK (phone ~ '^\+228[0-9]{8}$'),
  address_text     text NOT NULL CHECK (length(address_text) BETWEEN 1 AND 300),
  neighborhood_id  uuid REFERENCES neighborhoods (id),
  location         geography(Point, 4326) NOT NULL,
  logo_key         text,
  status           text NOT NULL DEFAULT 'pending_review'
                   CHECK (status IN ('pending_review', 'published', 'rejected', 'suspended')),
  status_reason    text NOT NULL DEFAULT '',
  accepting_orders boolean NOT NULL DEFAULT true,
  reviewed_at      timestamptz,
  reviewed_by      uuid REFERENCES users (id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX shops_owner_id_idx ON shops (owner_id);
CREATE INDEX shops_status_idx ON shops (status, created_at DESC);
CREATE INDEX shops_location_idx ON shops USING gist (location);
CREATE INDEX shops_name_trgm_idx ON shops USING gin (immutable_unaccent(lower(name)) gin_trgm_ops);

-- +goose Down
DROP TABLE shops;
