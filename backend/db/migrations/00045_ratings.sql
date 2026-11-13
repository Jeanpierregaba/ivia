-- Avis (spec 035) : note du livreur après une livraison (client, et marchand s'il le souhaite) et
-- avis sur l'application, lus par le back-office.

-- +goose Up
CREATE TABLE delivery_ratings (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id   uuid NOT NULL REFERENCES orders (id),
  driver_id  uuid NOT NULL REFERENCES drivers (user_id),
  rater_id   uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  rater_role text NOT NULL CHECK (rater_role IN ('buyer', 'seller')),
  stars      smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
  tags       text[] NOT NULL DEFAULT '{}' CHECK (cardinality(tags) <= 8),
  comment    text NOT NULL DEFAULT '' CHECK (length(comment) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Une note par commande et par rôle (client, marchand).
  UNIQUE (order_id, rater_role)
);
CREATE INDEX delivery_ratings_driver_idx ON delivery_ratings (driver_id, created_at DESC);
CREATE INDEX delivery_ratings_created_idx ON delivery_ratings (created_at DESC);

CREATE TABLE app_feedback (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  app        text NOT NULL CHECK (app IN ('buyer', 'seller', 'driver', 'pharmacy')),
  stars      smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment    text NOT NULL DEFAULT '' CHECK (length(comment) <= 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX app_feedback_created_idx ON app_feedback (created_at DESC);

-- +goose Down
DROP TABLE app_feedback;
DROP TABLE delivery_ratings;
