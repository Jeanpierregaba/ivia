-- Catégories de boutique (module shops), distinctes des catégories de produits du catalogue :
-- le catalogue dépend déjà des boutiques. Liste de départ, gérée plus tard dans le back-office.

-- +goose Up
CREATE TABLE shop_categories (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL UNIQUE CHECK (length(name) BETWEEN 1 AND 60),
  position   integer NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO shop_categories (name, position) VALUES
  ('Alimentation', 1),
  ('Mode et beauté', 2),
  ('Maison', 3),
  ('Électronique et téléphonie', 4),
  ('Santé et bien-être', 5),
  ('Services', 6),
  ('Autre', 7);

-- Nullable : les boutiques créées avant cette migration n'en ont pas.
ALTER TABLE shops ADD COLUMN category_id uuid REFERENCES shop_categories (id);

-- +goose Down
ALTER TABLE shops DROP COLUMN category_id;
DROP TABLE shop_categories;
