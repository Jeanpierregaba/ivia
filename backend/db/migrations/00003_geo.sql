-- Module geo : quartiers de la ville.

-- +goose Up
CREATE TABLE neighborhoods (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  city       text NOT NULL DEFAULT 'Lomé',
  name       text NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  center     geography(Point, 4326),
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (city, name)
);

-- +goose Down
DROP TABLE neighborhoods;
